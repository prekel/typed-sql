open! Base

type 'row t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; rows : Ast.assignment list list
  ; conflict : Ast.conflict option
  }

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

type 'row conflict =
  { insert : 'row t
  ; target : 'row Conflict_target.t
  }

module Conflict_update = struct
  type 'row assignment =
    | Assignment :
        ('row, 'base, 'value) Column.t * Ast.assignment_value
        -> 'row assignment

  type 'row t =
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
    set_expr column (Expr.param (Column.db_type column) value) update
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
      ; schema = Table.schema table
      ; table = Table.name table
      }
  ; rows = [ [] ]
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
  let rows =
    match List.rev insert.rows with
    | [] -> [ [ assignment ] ]
    | row :: rest -> List.rev ((row @ [ assignment ]) :: rest)
  in
  { insert with rows }
;;

let set column value insert =
  set_expr column (Expr.param (Column.db_type column) value) insert
;;

let default column insert =
  let assignment =
    { Ast.source_id = Table_ref.source_id insert.reference
    ; column = Column.name column
    ; value = Ast.Default
    }
  in
  let rows =
    match List.rev insert.rows with
    | [] -> [ [ assignment ] ]
    | row :: rest -> List.rev ((row @ [ assignment ]) :: rest)
  in
  { insert with rows }
;;

let rows table builders =
  let empty = into table in
  let rows =
    List.concat_map builders ~f:(fun build ->
      let built = build empty in
      built.rows)
  in
  { empty with rows }
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
  { Ast.kind = Ast.Insert
  ; source = insert.source
  ; assignments = []
  ; rows = insert.rows
  ; from = []
  ; conflict = insert.conflict
  ; where_ = None
  }
;;

let command insert = Command.create (ast insert)

let returning make_projection insert =
  let projection = make_projection insert.reference in
  Result_query.create
    (Ast.Returning
       { command = ast insert; projection = Projection.expressions projection })
    projection
;;
