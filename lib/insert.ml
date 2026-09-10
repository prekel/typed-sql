open! Base

type 'row t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; assignments : Ast.assignment list
  }

let into table =
  let reference = Table_ref.create table in
  { reference
  ; source =
      { Ast.source_id = Table_ref.source_id reference
      ; schema = Table.schema table
      ; table = Table.name table
      }
  ; assignments = []
  }
;;

let set_expr column expression insert =
  let assignment =
    { Ast.source_id = Table_ref.source_id insert.reference
    ; column = Column.name column
    ; value = Expr.Private.node expression
    }
  in
  { insert with assignments = insert.assignments @ [ assignment ] }
;;

let set column value insert =
  set_expr column (Expr.param (Column.db_type column) value) insert
;;

let ast insert =
  { Ast.kind = Ast.Insert
  ; source = insert.source
  ; assignments = insert.assignments
  ; where_ = None
  }
;;

let command insert = Command.Private.create (ast insert)

let returning make_projection insert =
  let projection = make_projection insert.reference in
  Result_query.Private.create
    (Ast.Returning
       { command = ast insert; projection = Projection.Private.expressions projection })
    projection
;;
