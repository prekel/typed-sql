open! Base

type ('ctx, 'result) t =
  { context : 'ctx
  ; projection : 'result Projection.t
  ; ast : Ast.select
  }

type direction =
  [ `Asc
  | `Desc
  ]

let from table ~select =
  let reference = Table_ref.create table in
  let projection = select reference in
  let source =
    { Ast.source_id = Table_ref.source_id reference
    ; schema = Table.schema table
    ; table = Table.name table
    }
  in
  { context = reference
  ; projection
  ; ast =
      { source
      ; projection = Projection.Private.expressions projection
      ; where_ = None
      ; order_by = []
      ; limit = None
      ; offset = None
      }
  }
;;

let select make_projection query =
  let projection = make_projection query.context in
  { context = query.context
  ; projection
  ; ast = { query.ast with projection = Projection.Private.expressions projection }
  }
;;

let where make_condition query =
  let condition = make_condition query.context |> Condition.Private.node in
  let where_ =
    match query.ast.where_ with
    | None -> Some condition
    | Some existing -> Some (Ast.And [ existing; condition ])
  in
  { query with ast = { query.ast with where_ } }
;;

let where_opt value ~f query =
  match value with
  | None -> query
  | Some value -> where (fun context -> f context value) query
;;

let order_by make_expression direction query =
  let expr = make_expression query.context |> Expr.Private.node in
  let direction =
    match direction with
    | `Asc -> Ast.Asc
    | `Desc -> Ast.Desc
  in
  let order = { Ast.expr; direction } in
  { query with ast = { query.ast with order_by = query.ast.order_by @ [ order ] } }
;;

let limit limit query = { query with ast = { query.ast with limit = Some limit } }
let offset offset query = { query with ast = { query.ast with offset = Some offset } }

module Private = struct
  let ast query = query.ast
  let projection query = query.projection
end
