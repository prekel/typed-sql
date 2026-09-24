open! Base

type ungrouped
type grouped

type ('ctx, 'grouping, +'cardinality, +'requirements) t =
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
    ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
    }
  in
  { context = reference
  ; ast =
      { ctes = []
      ; source
      ; joins = []
      ; distinct = false
      ; projection = []
      ; where_ = None
      ; group_by = []
      ; having = None
      ; order_by = []
      ; limit = None
      ; offset = None
      }
  }
;;

let source_of_reference reference =
  let table = Table_ref.table reference in
  { Ast.source_id = Table_ref.source_id reference
  ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
  }
;;

let source_of_derived reference relation =
  { Ast.source_id = Table_ref.source_id reference
  ; kind = Ast.Derived (Derived_table.relation relation)
  }
;;

let source_of_cte reference cte =
  { Ast.source_id = Table_ref.source_id reference; kind = Ast.Cte (Cte.id cte) }
;;

let from_derived relation =
  let reference = Table_ref.create (Derived_table.table relation) in
  { context = reference
  ; ast =
      { ctes = []
      ; source = source_of_derived reference relation
      ; joins = []
      ; distinct = false
      ; projection = []
      ; where_ = None
      ; group_by = []
      ; having = None
      ; order_by = []
      ; limit = None
      ; offset = None
      }
  }
;;

let from_relation relation =
  let reference = Derived_table.inferred_reference relation in
  { context = Derived_table.inferred_fields relation reference
  ; ast =
      { ctes = []
      ; source =
          { Ast.source_id = Table_ref.source_id reference
          ; kind = Ast.Derived (Derived_table.inferred_relation relation)
          }
      ; joins = []
      ; distinct = false
      ; projection = []
      ; where_ = None
      ; group_by = []
      ; having = None
      ; order_by = []
      ; limit = None
      ; offset = None
      }
  }
;;

let from_cte cte =
  let reference = Table_ref.create (Cte.table cte) in
  { context = reference
  ; ast =
      { ctes = []
      ; source = source_of_cte reference cte
      ; joins = []
      ; distinct = false
      ; projection = []
      ; where_ = None
      ; group_by = []
      ; having = None
      ; order_by = []
      ; limit = None
      ; offset = None
      }
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

let join_source kind ~table ~source ~on query =
  let reference = Table_ref.create table in
  let join =
    { Ast.kind
    ; source = source reference
    ; on = on query.context reference |> Condition.node
    }
  in
  reference, { query with ast = { query.ast with joins = query.ast.joins @ [ join ] } }
;;

let inner_join_derived relation ~on query =
  let reference, query =
    join_source
      Ast.Inner
      ~table:(Derived_table.table relation)
      ~source:(fun reference -> source_of_derived reference relation)
      ~on
      query
  in
  { context = query.context, reference; ast = query.ast }
;;

let left_join_derived relation ~on query =
  let reference, query =
    join_source
      Ast.Left
      ~table:(Derived_table.table relation)
      ~source:(fun reference -> source_of_derived reference relation)
      ~on
      query
  in
  { context = query.context, Nullable_table_ref.of_table_ref reference; ast = query.ast }
;;

let join_relation kind relation ~on query =
  let reference = Derived_table.inferred_reference relation in
  let fields = Derived_table.inferred_fields relation reference in
  let join =
    { Ast.kind
    ; source =
        { Ast.source_id = Table_ref.source_id reference
        ; kind = Ast.Derived (Derived_table.inferred_relation relation)
        }
    ; on = on query.context fields |> Condition.node
    }
  in
  reference, { query with ast = { query.ast with joins = query.ast.joins @ [ join ] } }
;;

let inner_join_relation relation ~on query =
  let reference, query = join_relation Ast.Inner relation ~on query in
  { context = query.context, Derived_table.inferred_fields relation reference
  ; ast = query.ast
  }
;;

let left_join_relation relation ~on query =
  let reference, query = join_relation Ast.Left relation ~on query in
  { context = query.context, Derived_table.inferred_nullable_fields relation reference
  ; ast = query.ast
  }
;;

let inner_join_cte cte ~on query =
  let reference, query =
    join_source
      Ast.Inner
      ~table:(Cte.table cte)
      ~source:(fun reference -> source_of_cte reference cte)
      ~on
      query
  in
  { context = query.context, reference; ast = query.ast }
;;

let left_join_cte cte ~on query =
  let reference, query =
    join_source
      Ast.Left
      ~table:(Cte.table cte)
      ~source:(fun reference -> source_of_cte reference cte)
      ~on
      query
  in
  { context = query.context, Nullable_table_ref.of_table_ref reference; ast = query.ast }
;;

let select make_projection query =
  let projection = make_projection query.context in
  let ast = { query.ast with projection = Projection.expressions projection } in
  Result_query.create_select (Ast.Simple ast) projection
;;

let multiset query =
  match Result_query.ast query with
  | Ast.Select select ->
    Projection.multiset_subquery select (Result_query.projection query)
  | Ast.Returning _ -> assert false
;;

let select_exactly_one make_projection query =
  let projection = make_projection query.context in
  let ast = { query.ast with projection = Projection.expressions projection } in
  Result_query.create_select ~requires_exactly_one:true (Ast.Simple ast) projection
;;

let select_relation make_fields query =
  let fields = make_fields query.context in
  Derived_table.create_inferred fields query.ast
;;

let set_operation operator left right =
  let left_ast =
    match Result_query.ast left with
    | Ast.Select query -> query
    | Ast.Returning _ -> assert false
  in
  let right_ast =
    match Result_query.ast right with
    | Ast.Select query -> query
    | Ast.Returning _ -> assert false
  in
  let compound =
    { Ast.ctes = []
    ; operator
    ; left = left_ast
    ; right = right_ast
    ; left_types = Projection.types (Result_query.projection left)
    ; right_types = Projection.types (Result_query.projection right)
    }
  in
  Result_query.create_select (Ast.Compound compound) (Result_query.projection left)
;;

let union left right = set_operation Ast.Union left right
let union_all left right = set_operation Ast.Union_all left right
let intersect left right = set_operation Ast.Intersect left right
let intersect_all left right = set_operation Ast.Intersect_all left right
let except left right = set_operation Ast.Except left right
let except_all left right = set_operation Ast.Except_all left right

let select_scalar make_expression query =
  let expression = make_expression query.context in
  let ast = { query.ast with projection = [ Expr.node expression ] } in
  Scalar_query.create ast (Expr.db_type expression)
;;

let exists query =
  let ast = { query.ast with projection = [] } in
  Condition.create (Ast.Exists ast)
;;

let not_exists query =
  let ast = { query.ast with projection = [] } in
  Condition.create (Ast.Not_exists ast)
;;

let in_subquery expression query =
  Condition.create (Ast.In_subquery (Expr.node expression, Scalar_query.ast query))
;;

let not_in_subquery expression query =
  Condition.create (Ast.Not_in_subquery (Expr.node expression, Scalar_query.ast query))
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

let where_optional_param parameter ~f query =
  where
    (fun context -> Condition.Infix.(Expr.is_null parameter ||. f context parameter))
    query
;;

let distinct query = { query with ast = { query.ast with distinct = true } }

let group_by make_expression query =
  let expression = make_expression query.context |> Expr.node in
  { query with ast = { query.ast with group_by = query.ast.group_by @ [ expression ] } }
;;

let having make_condition query =
  let condition = make_condition query.context |> Condition.node in
  let having =
    match query.ast.having with
    | None -> Some condition
    | Some existing -> Some (Ast.And [ existing; condition ])
  in
  { query with ast = { query.ast with having } }
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

let limit limit query =
  { query with ast = { query.ast with limit = Some (Ast.Literal limit) } }
;;

let limit_one query = { query with ast = { query.ast with limit = Some (Ast.Literal 1) } }

let offset offset query =
  { query with ast = { query.ast with offset = Some (Ast.Literal offset) } }
;;

let limit_param parameter query =
  { query with
    ast =
      { query.ast with
        limit = Some (Ast.Parameter (Pagination_parameter.node parameter))
      }
  }
;;

let offset_param parameter query =
  { query with
    ast =
      { query.ast with
        offset = Some (Ast.Parameter (Pagination_parameter.node parameter))
      }
  }
;;

let ast query = query.ast
