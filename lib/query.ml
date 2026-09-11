open! Base

type 'ctx t =
  { context : 'ctx
  ; ast : Ast.select
  }

type direction =
  [ `Asc
  | `Desc
  ]

let from table =
  let reference = Table_ref.create table in
  let source =
    { Ast.source_id = Table_ref.source_id reference
    ; schema = Table.schema table
    ; table = Table.name table
    }
  in
  { context = reference
  ; ast =
      { source
      ; joins = []
      ; projection = []
      ; where_ = None
      ; order_by = []
      ; limit = None
      ; offset = None
      }
  }
;;

let source_of_reference reference =
  let table = Table_ref.table reference in
  { Ast.source_id = Table_ref.source_id reference
  ; schema = Table.schema table
  ; table = Table.name table
  }
;;

let inner_join table ~on query =
  let reference = Table_ref.create table in
  let join =
    { Ast.kind = Ast.Inner
    ; source = source_of_reference reference
    ; on = on query.context reference |> Condition.node
    }
  in
  { context = query.context, reference
  ; ast = { query.ast with joins = query.ast.joins @ [ join ] }
  }
;;

let left_join table ~on query =
  let reference = Table_ref.create table in
  let join =
    { Ast.kind = Ast.Left
    ; source = source_of_reference reference
    ; on = on query.context reference |> Condition.node
    }
  in
  { context = query.context, Nullable_table_ref.of_table_ref reference
  ; ast = { query.ast with joins = query.ast.joins @ [ join ] }
  }
;;

let select make_projection query =
  let projection = make_projection query.context in
  let ast = { query.ast with projection = Projection.expressions projection } in
  Result_query.create (Ast.Select ast) projection
;;

let where make_condition query =
  let condition = make_condition query.context |> Condition.node in
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
  let expr = make_expression query.context |> Expr.node in
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
let ast query = query.ast
