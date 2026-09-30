open! Base

type ('row, +'requirements) t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; input : Ast.insert_input
  ; conflict : Ast.conflict option
  }

module Columns = struct
  type 'row column = Column : ('row, 'base, 'value) Column.t -> 'row column
  type 'row t = 'row column list

  let column column = [ Column column ]
  let add column columns = columns @ [ Column column ]

  let targets reference columns =
    List.map columns ~f:(fun (Column column) ->
      { Ast.target_source_id = Column.source_id_for reference column
      ; target_column = Column.name column
      ; target_type = Db_type.Pack (Column.db_type column)
      })
  ;;
end

module Conflict_target = struct
  type 'row column = Column : ('row, 'base, 'value) Column.t -> 'row column
  type 'row t = 'row column list

  let column column = [ Column column ]
  let add column target = target @ [ Column column ]

  let columns reference target =
    List.map target ~f:(fun (Column column) ->
      { Ast.target_source_id = Column.source_id_for reference column
      ; target_column = Column.name column
      })
  ;;
end

type ('row, +'requirements) conflict =
  { insert : ('row, 'requirements) t
  ; target : 'row Conflict_target.t
  }

module Conflict_update = struct
  type 'row assignment =
    | Assignment :
        ('row, 'base, 'value) Column.t * Ast.assignment_value
        -> 'row assignment

  type ('row, +'requirements) t =
    { assignments : 'row assignment list
    ; where_ : Ast.condition option
    }

  let empty = { assignments = []; where_ = None }

  let set_expr column expression update =
    { update with
      assignments =
        update.assignments
        @ [ Assignment (column, Ast.Expression (Expr.node expression)) ]
    }
  ;;

  let set column value update =
    set_expr column (Expr.constant (Column.db_type column) value) update
  ;;

  let set_opt column value update =
    match value with
    | None -> update
    | Some value -> set column value update
  ;;

  let set_expr_opt column expression update =
    match expression with
    | None -> update
    | Some expression -> set_expr column expression update
  ;;

  let where condition update =
    let condition = Condition.node condition in
    let where_ =
      match update.where_ with
      | None -> Some condition
      | Some previous -> Some (Ast.And [ previous; condition ])
    in
    { update with where_ }
  ;;
end

let into table =
  let reference = Table_ref.create table in
  { reference
  ; source =
      { Ast.source_id = Table_ref.source_id reference
      ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
      }
  ; input = Ast.Rows [ [] ]
  ; conflict = None
  }
;;

let set_expr column expression insert =
  let assignment =
    { Ast.source_id = Table_ref.source_id insert.reference
    ; column = Column.name column
    ; value = Ast.Expression (Expr.node expression)
    }
  in
  let input =
    match insert.input with
    | Ast.Rows rows ->
      let rows =
        match List.rev rows with
        | [] -> [ [ assignment ] ]
        | row :: rest -> List.rev ((row @ [ assignment ]) :: rest)
      in
      Ast.Rows rows
    | Ast.Select_rows _ | Ast.Mixed_sources -> Ast.Mixed_sources
  in
  { insert with input }
;;

let set column value insert =
  set_expr column (Expr.constant (Column.db_type column) value) insert
;;

let default column insert =
  let assignment =
    { Ast.source_id = Table_ref.source_id insert.reference
    ; column = Column.name column
    ; value = Ast.Default
    }
  in
  let input =
    match insert.input with
    | Ast.Rows rows ->
      let rows =
        match List.rev rows with
        | [] -> [ [ assignment ] ]
        | row :: rest -> List.rev ((row @ [ assignment ]) :: rest)
      in
      Ast.Rows rows
    | Ast.Select_rows _ | Ast.Mixed_sources -> Ast.Mixed_sources
  in
  { insert with input }
;;

let rows table builders =
  let empty = into table in
  let input =
    List.fold builders ~init:(Ast.Rows []) ~f:(fun input build ->
      match input, (build empty).input with
      | Ast.Rows accumulated, Ast.Rows rows -> Ast.Rows (accumulated @ rows)
      | _ -> Ast.Mixed_sources)
  in
  { empty with input }
;;

let from_select columns query insert =
  let input =
    match insert.input with
    | Ast.Rows [ [] ] ->
      let result_types = Projection.types (Result_query.projection query) in
      let query_ast =
        match Result_query.ast query with
        | Ast.Select query -> query
        | Ast.Returning _ -> assert false
      in
      Ast.Select_rows
        { columns = Columns.targets insert.reference columns
        ; query = query_ast
        ; result_types
        }
    | Ast.Rows _ | Ast.Select_rows _ | Ast.Mixed_sources -> Ast.Mixed_sources
  in
  { insert with input }
;;

let on_conflict_do_nothing insert = { insert with conflict = Some (Ast.Do_nothing None) }
let on_conflict target insert = { insert; target }

let do_nothing conflict =
  let insert = conflict.insert in
  { conflict.insert with
    conflict =
      Some
        (Ast.Do_nothing (Some (Conflict_target.columns insert.reference conflict.target)))
  }
;;

let do_update make_update conflict =
  let insert = conflict.insert in
  let excluded = Table_ref.create (Table_ref.table insert.reference) in
  let update : _ Conflict_update.t = make_update ~existing:insert.reference ~excluded in
  let assignments =
    List.map update.assignments ~f:(fun (Conflict_update.Assignment (column, value)) ->
      { Ast.source_id = Column.source_id_for insert.reference column
      ; column = Column.name column
      ; value
      })
  in
  { insert with
    conflict =
      Some
        (Ast.Do_update
           { target = Conflict_target.columns insert.reference conflict.target
           ; excluded_source_id = Table_ref.source_id excluded
           ; assignments
           ; where_ = update.where_
           })
  }
;;

let ast insert =
  { Ast.ctes = []
  ; kind = Ast.Insert
  ; source = insert.source
  ; assignments = []
  ; insert_input = Some insert.input
  ; from = []
  ; conflict = insert.conflict
  ; where_ = None
  }
;;

let command insert = Command.create (ast insert)

let returning make_projection insert =
  let projection = make_projection insert.reference in
  Result_query.create_returning
    { Ast.command = ast insert; projection = Projection.expressions projection }
    projection
;;
