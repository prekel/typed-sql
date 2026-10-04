open! Base

let rec expression_sources = function
  | Ast.Column { source_id; _ } -> [ source_id ]
  | Ast.Param _
  | Ast.Current_timestamp
  | Ast.Scalar_subquery _
  | Ast.Multiset_subquery _
  | Ast.Exists_expr _ -> []
  | Ast.Arithmetic (_, left, right) | Ast.Concat (left, right) | Ast.Coalesce (left, right)
    -> expression_sources left @ expression_sources right
  | Ast.Cast (_, _, expression) | Ast.String_function (_, expression) ->
    expression_sources expression
  | Ast.Case (branches, else_) ->
    List.concat_map branches ~f:(fun (condition, expression) ->
      condition_sources condition @ expression_sources expression)
    @ expression_sources else_
  | Ast.Aggregate aggregate -> aggregate_sources aggregate

and condition_sources = function
  | Ast.True | Ast.False | Ast.Exists _ | Ast.Not_exists _ -> []
  | Ast.Compare (_, left, right) | Ast.Equals_any (left, right) ->
    expression_sources left @ expression_sources right
  | Ast.Is_null expression | Ast.Is_not_null expression -> expression_sources expression
  | Ast.In (expression, values) | Ast.Not_in (expression, values) ->
    expression_sources expression @ List.concat_map values ~f:expression_sources
  | Ast.Between (expression, lower, upper) ->
    expression_sources expression @ expression_sources lower @ expression_sources upper
  | Ast.In_subquery (expression, _) | Ast.Not_in_subquery (expression, _) ->
    expression_sources expression
  | Ast.And conditions | Ast.Or conditions ->
    List.concat_map conditions ~f:condition_sources
  | Ast.Not condition -> condition_sources condition

and aggregate_sources = function
  | Ast.Count_all -> []
  | Ast.Count expression
  | Ast.Count_distinct expression
  | Ast.Sum_int expression
  | Ast.Sum_float expression
  | Ast.Sum_int64 expression
  | Ast.Sum_numeric expression
  | Ast.Avg_float expression
  | Ast.Avg_numeric expression
  | Ast.Min expression
  | Ast.Max expression -> expression_sources expression
  | Ast.String_agg { value; delimiter; order_by } ->
    expression_sources value
    @ expression_sources delimiter
    @ List.concat_map order_by ~f:(fun order -> expression_sources order.Ast.expr)
  | Ast.Multiset_agg multiset ->
    List.concat_map multiset.fields ~f:expression_sources
    @ List.concat_map multiset.order_by ~f:(fun order ->
      expression_sources order.Ast.expr)
    @ Option.value_map multiset.filter ~default:[] ~f:condition_sources
;;

let aggregate_is_local ~sources aggregate =
  let referenced_sources = aggregate_sources aggregate in
  List.is_empty referenced_sources
  || List.exists referenced_sources ~f:(fun source_id ->
    List.mem sources source_id ~equal:Int.equal)
;;

let rec expression_has_local_aggregate ~sources = function
  | Ast.Aggregate aggregate -> aggregate_is_local ~sources aggregate
  | Ast.Param _
  | Ast.Column _
  | Ast.Current_timestamp
  | Ast.Scalar_subquery _
  | Ast.Multiset_subquery _
  | Ast.Exists_expr _ -> false
  | Ast.Arithmetic (_, left, right) | Ast.Concat (left, right) | Ast.Coalesce (left, right)
    ->
    expression_has_local_aggregate ~sources left
    || expression_has_local_aggregate ~sources right
  | Ast.Cast (_, _, expression) | Ast.String_function (_, expression) ->
    expression_has_local_aggregate ~sources expression
  | Ast.Case (branches, else_) ->
    expression_has_local_aggregate ~sources else_
    || List.exists branches ~f:(fun (condition, expression) ->
      condition_has_local_aggregate ~sources condition
      || expression_has_local_aggregate ~sources expression)

and condition_has_local_aggregate ~sources = function
  | Ast.True | Ast.False | Ast.Exists _ | Ast.Not_exists _ -> false
  | Ast.Compare (_, left, right) | Ast.Equals_any (left, right) ->
    expression_has_local_aggregate ~sources left
    || expression_has_local_aggregate ~sources right
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    expression_has_local_aggregate ~sources expression
  | Ast.In (expression, values) | Ast.Not_in (expression, values) ->
    expression_has_local_aggregate ~sources expression
    || List.exists values ~f:(expression_has_local_aggregate ~sources)
  | Ast.Between (expression, lower, upper) ->
    expression_has_local_aggregate ~sources expression
    || expression_has_local_aggregate ~sources lower
    || expression_has_local_aggregate ~sources upper
  | Ast.In_subquery (expression, _) | Ast.Not_in_subquery (expression, _) ->
    expression_has_local_aggregate ~sources expression
  | Ast.And conditions | Ast.Or conditions ->
    List.exists conditions ~f:(condition_has_local_aggregate ~sources)
  | Ast.Not condition -> condition_has_local_aggregate ~sources condition
;;

let projection_has_local_aggregate (select : Ast.select) =
  let sources =
    select.source.source_id
    :: List.map select.joins ~f:(fun join -> join.Ast.source.source_id)
  in
  List.exists select.projection ~f:(expression_has_local_aggregate ~sources)
;;

let at_most_one (select : Ast.select) =
  Option.exists select.limit ~f:(function
    | Ast.Limit (Ast.Literal limit) -> Int.(limit >= 0 && limit <= 1)
    | Ast.Limit (Ast.Parameter _) | Ast.Fetch_with_ties _ -> false)
  || (List.is_empty select.group_by && projection_has_local_aggregate select)
;;

let exactly_one (select : Ast.select) =
  List.is_empty select.group_by
  && Option.is_none select.having
  && Option.is_none select.offset
  && projection_has_local_aggregate select
  &&
  match select.limit with
  | None -> true
  | Some (Ast.Limit (Ast.Literal limit) | Ast.Fetch_with_ties (Ast.Literal limit)) ->
    Int.(limit > 0)
  | Some (Ast.Limit (Ast.Parameter _) | Ast.Fetch_with_ties (Ast.Parameter _)) -> false
;;
