open! Base

type 'row t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; rows : Ast.assignment list list
  ; conflict : Ast.conflict option
  }

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

let on_conflict_do_nothing insert = { insert with conflict = Some Ast.Do_nothing }

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
