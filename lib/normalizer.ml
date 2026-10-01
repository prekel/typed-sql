open! Base

let rec normalize_expr = function
  | Ast.Column _ as expression -> expression
  | Ast.Param _ as expression -> expression
  | Ast.Arithmetic (operator, left, right) ->
    Ast.Arithmetic (operator, normalize_expr left, normalize_expr right)
  | Ast.String_function (function_, expression) ->
    Ast.String_function (function_, normalize_expr expression)
  | Ast.Concat (left, right) -> Ast.Concat (normalize_expr left, normalize_expr right)
  | Ast.Coalesce (left, right) -> Ast.Coalesce (normalize_expr left, normalize_expr right)
  | Ast.Case ([], else_) -> normalize_expr else_
  | Ast.Case (branches, else_) ->
    Ast.Case
      ( List.map branches ~f:(fun (condition, expression) ->
          normalize_condition condition, normalize_expr expression)
      , normalize_expr else_ )
  | Ast.Aggregate Ast.Count_all as expression -> expression
  | Ast.Aggregate (Ast.Count expression) ->
    Ast.Aggregate (Ast.Count (normalize_expr expression))
  | Ast.Aggregate (Ast.Count_distinct expression) ->
    Ast.Aggregate (Ast.Count_distinct (normalize_expr expression))
  | Ast.Aggregate (Ast.Sum_int expression) ->
    Ast.Aggregate (Ast.Sum_int (normalize_expr expression))
  | Ast.Aggregate (Ast.Sum_float expression) ->
    Ast.Aggregate (Ast.Sum_float (normalize_expr expression))
  | Ast.Aggregate (Ast.Sum_int64 expression) ->
    Ast.Aggregate (Ast.Sum_int64 (normalize_expr expression))
  | Ast.Aggregate (Ast.Sum_numeric expression) ->
    Ast.Aggregate (Ast.Sum_numeric (normalize_expr expression))
  | Ast.Aggregate (Ast.Min expression) ->
    Ast.Aggregate (Ast.Min (normalize_expr expression))
  | Ast.Aggregate (Ast.Max expression) ->
    Ast.Aggregate (Ast.Max (normalize_expr expression))
  | Ast.Aggregate (Ast.String_agg string_agg) ->
    Ast.Aggregate
      (Ast.String_agg
         { value = normalize_expr string_agg.value
         ; delimiter = normalize_expr string_agg.delimiter
         ; order_by =
             List.map string_agg.order_by ~f:(fun order ->
               { order with Ast.expr = normalize_expr order.expr })
         })
  | Ast.Aggregate (Ast.Multiset_agg multiset) ->
    Ast.Aggregate
      (Ast.Multiset_agg
         { multiset with
           Ast.fields = List.map multiset.fields ~f:normalize_expr
         ; filter = Option.map multiset.filter ~f:normalize_condition
         ; order_by =
             List.map multiset.order_by ~f:(fun order ->
               { order with Ast.expr = normalize_expr order.expr })
         })
  | Ast.Scalar_subquery select -> Ast.Scalar_subquery (normalize_select select)
  | Ast.Multiset_subquery multiset ->
    Ast.Multiset_subquery
      { multiset with Ast.query = normalize_select_query multiset.query }
  | Ast.Exists_expr select -> Ast.Exists_expr (normalize_select select)
  | Ast.Current_timestamp as expression -> expression

and normalize_condition condition =
  let rec normalize = function
    | Ast.True -> Ast.True
    | Ast.False -> Ast.False
    | Ast.Compare (comparison, left, right) ->
      Ast.Compare (comparison, normalize_expr left, normalize_expr right)
    | Ast.Equals_any (left, right) ->
      Ast.Equals_any (normalize_expr left, normalize_expr right)
    | Ast.Is_null expression -> Ast.Is_null (normalize_expr expression)
    | Ast.Is_not_null expression -> Ast.Is_not_null (normalize_expr expression)
    | Ast.In (_, []) -> Ast.False
    | Ast.Not_in (_, []) -> Ast.True
    | Ast.In (expression, values) ->
      Ast.In (normalize_expr expression, List.map values ~f:normalize_expr)
    | Ast.Not_in (expression, values) ->
      Ast.Not_in (normalize_expr expression, List.map values ~f:normalize_expr)
    | Ast.Between (expression, lower, upper) ->
      Ast.Between (normalize_expr expression, normalize_expr lower, normalize_expr upper)
    | Ast.Exists select -> Ast.Exists (normalize_select select)
    | Ast.Not_exists select -> Ast.Not_exists (normalize_select select)
    | Ast.In_subquery (expression, select) ->
      Ast.In_subquery (normalize_expr expression, normalize_select select)
    | Ast.Not_in_subquery (expression, select) ->
      Ast.Not_in_subquery (normalize_expr expression, normalize_select select)
    | Ast.Not condition ->
      (match normalize condition with
       | Ast.True -> Ast.False
       | Ast.False -> Ast.True
       | Ast.Not nested -> normalize nested
       | condition -> Ast.Not condition)
    | Ast.And conditions -> normalize_and conditions
    | Ast.Or conditions -> normalize_or conditions
  and normalize_and conditions =
    let conditions =
      List.concat_map conditions ~f:(fun condition ->
        match normalize condition with
        | Ast.And nested -> nested
        | condition -> [ condition ])
    in
    if
      List.exists conditions ~f:(function
        | Ast.False -> true
        | _ -> false)
    then
      Ast.False
    else (
      match
        List.filter conditions ~f:(function
          | Ast.True -> false
          | _ -> true)
      with
      | [] -> Ast.True
      | [ condition ] -> condition
      | conditions -> Ast.And conditions)
  and normalize_or conditions =
    let conditions =
      List.concat_map conditions ~f:(fun condition ->
        match normalize condition with
        | Ast.Or nested -> nested
        | condition -> [ condition ])
    in
    if
      List.exists conditions ~f:(function
        | Ast.True -> true
        | _ -> false)
    then
      Ast.True
    else (
      match
        List.filter conditions ~f:(function
          | Ast.False -> false
          | _ -> true)
      with
      | [] -> Ast.False
      | [ condition ] -> condition
      | conditions -> Ast.Or conditions)
  in
  normalize condition

and normalize_select (select : Ast.select) =
  let optional = function
    | None -> None
    | Some condition ->
      (match normalize_condition condition with
       | Ast.True -> None
       | condition -> Some condition)
  in
  { select with
    Ast.ctes = List.map select.ctes ~f:normalize_cte
  ; source = normalize_source select.source
  ; projection = List.map select.projection ~f:normalize_expr
  ; where_ = optional select.where_
  ; group_by = List.map select.group_by ~f:normalize_expr
  ; having = Option.map select.having ~f:normalize_condition
  ; order_by =
      List.map select.order_by ~f:(fun order ->
        { order with Ast.expr = normalize_expr order.expr })
  ; joins =
      List.map select.joins ~f:(fun (join : Ast.join) ->
        { join with
          Ast.source = normalize_source join.source
        ; on = normalize_condition join.on
        })
  }

and normalize_select_query = function
  | Ast.Simple select -> Ast.Simple (normalize_select select)
  | Ast.Source_free source_free ->
    Ast.Source_free
      { ctes = List.map source_free.ctes ~f:normalize_cte
      ; expression = normalize_expr source_free.expression
      }
  | Ast.Compound compound ->
    Ast.Compound
      { compound with
        Ast.ctes = List.map compound.ctes ~f:normalize_cte
      ; left = normalize_select_query compound.left
      ; right = normalize_select_query compound.right
      }

and normalize_relation (relation : Ast.relation) =
  { relation with
    Ast.query = normalize_select_query relation.query
  ; columns = List.map relation.columns ~f:normalize_expr
  }

and normalize_source (source : Ast.source) =
  let kind =
    match source.Ast.kind with
    | (Ast.Table _ | Ast.Cte _) as kind -> kind
    | Ast.Derived relation -> Ast.Derived (normalize_relation relation)
    | Ast.Values values ->
      Ast.Values
        { values with
          Ast.rows =
            List.map values.rows ~f:(fun row ->
              { row with Ast.expressions = List.map row.expressions ~f:normalize_expr })
        }
  in
  { source with Ast.kind }

and normalize_cte (cte : Ast.cte) =
  let body =
    match cte.Ast.body with
    | Ast.Select_body query -> Ast.Select_body (normalize_select_query query)
    | Ast.Recursive_body recursive ->
      Ast.Recursive_body
        { recursive with
          anchor = normalize_relation recursive.anchor
        ; step = normalize_relation recursive.step
        }
    | Ast.Returning_body returning -> Ast.Returning_body (normalize_returning returning)
    | Ast.Command_body command -> Ast.Command_body (normalize_command command)
  in
  { cte with Ast.columns = List.map cte.columns ~f:normalize_expr; body }

and normalize_returning (returning : Ast.returning) =
  { Ast.command = normalize_command returning.Ast.command
  ; projection = List.map returning.projection ~f:normalize_expr
  }

and normalize_command (command : Ast.command) =
  { command with
    Ast.ctes = List.map command.ctes ~f:normalize_cte
  ; source = normalize_source command.source
  ; from = List.map command.from ~f:normalize_source
  ; assignments = List.map command.assignments ~f:normalize_assignment
  ; insert_input = Option.map command.insert_input ~f:normalize_insert_input
  ; conflict = Option.map command.conflict ~f:normalize_conflict
  ; where_ = optional_condition command.where_
  }

and normalize_insert_input = function
  | Ast.Rows rows -> Ast.Rows (List.map rows ~f:(List.map ~f:normalize_assignment))
  | Ast.Select_rows selected ->
    Ast.Select_rows { selected with query = normalize_select_query selected.query }
  | Ast.Mixed_sources -> Ast.Mixed_sources

and optional_condition = function
  | None -> None
  | Some value ->
    (match normalize_condition value with
     | Ast.True -> None
     | condition -> Some condition)

and normalize_assignment assignment =
  let value =
    match assignment.Ast.value with
    | Ast.Default -> Ast.Default
    | Ast.Expression expression -> Ast.Expression (normalize_expr expression)
  in
  { assignment with Ast.value }

and normalize_conflict = function
  | Ast.Do_nothing _ as conflict -> conflict
  | Ast.Do_update update ->
    Ast.Do_update
      { update with
        assignments = List.map update.assignments ~f:normalize_assignment
      ; where_ = optional_condition update.where_
      }
;;

let select = normalize_select
let select_query = normalize_select_query
let command = normalize_command

let result_query = function
  | Ast.Select query -> Ast.Select (select_query query)
  | Ast.Returning returning -> Ast.Returning (normalize_returning returning)
;;
