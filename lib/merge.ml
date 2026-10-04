open! Base

type without_source
type without_on
type ready

type _ stage_state =
  | Awaiting_source : without_source stage_state
  | Awaiting_on : Ast.source -> without_on stage_state
  | Ready : Ast.source * Ast.condition -> ready stage_state

type ('row, 'source_ctx, 'stage, +'requirements) t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; context : 'source_ctx
  ; stage_state : 'stage stage_state
  ; branches : Ast.merge_branch list
  }

module Assignments = struct
  type 'row assignment =
    | Assignment :
        ('row, 'base, 'value) Column.t * Ast.assignment_value
        -> 'row assignment

  type ('row, +'requirements) t = 'row assignment list

  let empty = []

  let set_expr column expression assignments =
    assignments @ [ Assignment (column, Ast.Expression (Expr.node expression)) ]
  ;;

  let set column value assignments =
    set_expr column (Expr.constant (Column.db_type column) value) assignments
  ;;

  let default column assignments = assignments @ [ Assignment (column, Ast.Default) ]

  let ast reference assignments =
    List.map assignments ~f:(fun (Assignment (column, value)) ->
      { Ast.source_id = Column.source_id_for reference column
      ; column = Column.name column
      ; value
      })
  ;;
end

let into table =
  let reference = Table_ref.create table in
  { reference
  ; source =
      { Ast.source_id = Table_ref.source_id reference
      ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
      }
  ; context = ()
  ; stage_state = Awaiting_source
  ; branches = []
  }
;;

let using_source ~context ~source ~f (merge : (_, _, without_source, _) t) =
  let merge = { merge with context; stage_state = Awaiting_on source } in
  f merge.reference context merge
;;

let using table ~f merge =
  let reference = Table_ref.create table in
  let source =
    { Ast.source_id = Table_ref.source_id reference
    ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
    }
  in
  using_source ~context:reference ~source ~f merge
;;

let using_derived relation ~f merge =
  let reference = Table_ref.create (Derived_table.table relation) in
  let source =
    { Ast.source_id = Table_ref.source_id reference
    ; kind = Ast.Derived (Derived_table.relation relation)
    }
  in
  using_source ~context:reference ~source ~f merge
;;

let using_relation relation ~f merge =
  let reference = Derived_table.inferred_reference relation in
  let source =
    { Ast.source_id = Table_ref.source_id reference
    ; kind = Ast.Derived (Derived_table.inferred_relation relation)
    }
  in
  using_source
    ~context:(Derived_table.inferred_fields relation reference)
    ~source
    ~f
    merge
;;

let using_values values ~f merge =
  let reference = Table_ref.create (Values.table values) in
  using_source ~context:reference ~source:(Values.source values reference) ~f merge
;;

let using_cte cte ~f merge =
  let reference = Table_ref.create (Cte.table cte) in
  let source =
    { Ast.source_id = Table_ref.source_id reference; kind = Ast.Cte (Cte.id cte) }
  in
  using_source ~context:reference ~source ~f merge
;;

let using_cte_relation cte ~f merge =
  let reference = Cte.inferred_reference cte in
  let source =
    { Ast.source_id = Table_ref.source_id reference
    ; kind = Ast.Cte (Cte.inferred_id cte)
    }
  in
  using_source ~context:(Cte.inferred_fields cte reference) ~source ~f merge
;;

let on condition (merge : (_, _, without_on, _) t) =
  match merge.stage_state with
  | Awaiting_on source ->
    { merge with stage_state = Ready (source, Condition.node condition) }
;;

let when_matched_update ?condition assignments merge =
  let branch =
    Ast.Matched
      { condition = Option.map condition ~f:Condition.node
      ; action = Ast.Merge_update (Assignments.ast merge.reference assignments)
      }
  in
  { merge with branches = merge.branches @ [ branch ] }
;;

let when_matched_delete ?condition merge =
  let branch =
    Ast.Matched
      { condition = Option.map condition ~f:Condition.node; action = Ast.Merge_delete }
  in
  { merge with branches = merge.branches @ [ branch ] }
;;

let when_matched_do_nothing ?condition merge =
  let branch =
    Ast.Matched
      { condition = Option.map condition ~f:Condition.node
      ; action = Ast.Merge_matched_do_nothing
      }
  in
  { merge with branches = merge.branches @ [ branch ] }
;;

let when_not_matched_insert ?condition assignments merge =
  let branch =
    Ast.Not_matched
      { condition = Option.map condition ~f:Condition.node
      ; action = Ast.Merge_insert (Assignments.ast merge.reference assignments)
      }
  in
  { merge with branches = merge.branches @ [ branch ] }
;;

let when_not_matched_do_nothing ?condition merge =
  let branch =
    Ast.Not_matched
      { condition = Option.map condition ~f:Condition.node
      ; action = Ast.Merge_not_matched_do_nothing
      }
  in
  { merge with branches = merge.branches @ [ branch ] }
;;

let ast (merge : (_, _, ready, _) t) =
  let (Ready (using, on)) = merge.stage_state in
  { Ast.ctes = []
  ; kind = Ast.Merge { using; on; branches = merge.branches }
  ; source = merge.source
  ; assignments = []
  ; insert_input = None
  ; from = []
  ; conflict = None
  ; where_ = None
  }
;;

let command merge = Command.create (ast merge)

let returning make_projection merge =
  let projection = make_projection merge.reference merge.context in
  Result_query.create_returning
    { Ast.command = ast merge; projection = Projection.expressions projection }
    projection
;;
