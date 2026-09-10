open! Base

type unscoped
type scoped

type ('row, 'scope) t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; assignments : Ast.assignment list
  ; where_ : Ast.condition option
  }

let table table =
  let reference = Table_ref.create table in
  { reference
  ; source =
      { Ast.source_id = Table_ref.source_id reference
      ; schema = Table.schema table
      ; table = Table.name table
      }
  ; assignments = []
  ; where_ = None
  }
;;

let set_expr column expression update =
  let assignment =
    { Ast.source_id = Table_ref.source_id update.reference
    ; column = Column.name column
    ; value = Expr.Private.node expression
    }
  in
  { update with assignments = update.assignments @ [ assignment ] }
;;

let set column value update =
  set_expr column (Expr.param (Column.db_type column) value) update
;;

let where make_condition update =
  let condition = make_condition update.reference |> Condition.Private.node in
  let where_ =
    match update.where_ with
    | None -> Some condition
    | Some existing -> Some (Ast.And [ existing; condition ])
  in
  { update with where_ }
;;

let all_rows update = { update with where_ = None }

let ast update =
  { Ast.kind = Ast.Update
  ; source = update.source
  ; assignments = update.assignments
  ; where_ = update.where_
  }
;;

let command update = Command.Private.create (ast update)

let returning make_projection update =
  let projection = make_projection update.reference in
  Result_query.Private.create
    (Ast.Returning
       { command = ast update; projection = Projection.Private.expressions projection })
    projection
;;
