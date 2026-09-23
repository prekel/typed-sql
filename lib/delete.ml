open! Base

type unscoped
type scoped

type ('row, 'scope, +'requirements) t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; where_ : Ast.condition option
  }

let from table =
  let reference = Table_ref.create table in
  { reference
  ; source =
      { Ast.source_id = Table_ref.source_id reference
      ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
      }
  ; where_ = None
  }
;;

let where make_condition delete =
  let condition = make_condition delete.reference |> Condition.node in
  let where_ =
    match delete.where_ with
    | None -> Some condition
    | Some existing -> Some (Ast.And [ existing; condition ])
  in
  { delete with where_ }
;;

let all_rows delete = { delete with where_ = None }

let ast delete =
  { Ast.ctes = []
  ; kind = Ast.Delete
  ; source = delete.source
  ; assignments = []
  ; rows = []
  ; from = []
  ; conflict = None
  ; where_ = delete.where_
  }
;;

let command delete = Command.create (ast delete)

let returning make_projection delete =
  let projection = make_projection delete.reference in
  Result_query.create_returning
    { Ast.command = ast delete; projection = Projection.expressions projection }
    projection
;;
