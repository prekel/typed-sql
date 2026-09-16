open! Base

let rec normalize_expr = function
  | Ast.Column _ as expression -> expression
  | Ast.Param _ as expression -> expression
  | Ast.Arithmetic (operator, left, right) ->
    Ast.Arithmetic (operator, normalize_expr left, normalize_expr right)
  | Ast.String_function (function_, expression) ->
    Ast.String_function (function_, normalize_expr expression)
  | Ast.Concat (left, right) -> Ast.Concat (normalize_expr left, normalize_expr right)
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
  | Ast.Scalar_subquery select -> Ast.Scalar_subquery (normalize_select select)
  | Ast.Current_timestamp as expression -> expression

and normalize_condition condition =
  let rec normalize = function
    | Ast.True -> Ast.True
    | Ast.False -> Ast.False
    | Ast.Compare (comparison, left, right) ->
      Ast.Compare (comparison, normalize_expr left, normalize_expr right)
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
    Ast.projection = List.map select.projection ~f:normalize_expr
  ; where_ = optional select.where_
  ; group_by = List.map select.group_by ~f:normalize_expr
  ; having = Option.map select.having ~f:normalize_condition
  ; order_by =
      List.map select.order_by ~f:(fun order ->
        { order with Ast.expr = normalize_expr order.expr })
  ; joins =
      List.map select.joins ~f:(fun (join : Ast.join) ->
        { join with Ast.on = normalize_condition join.on })
  }
;;

let optional_condition = function
  | None -> None
  | Some value ->
    (match normalize_condition value with
     | Ast.True -> None
     | condition -> Some condition)
;;

let normalize_assignment assignment =
  let value =
    match assignment.Ast.value with
    | Ast.Default -> Ast.Default
    | Ast.Expression expression -> Ast.Expression (normalize_expr expression)
  in
  { assignment with Ast.value }
;;

let normalize_conflict = function
  | Ast.Do_nothing _ as conflict -> conflict
  | Ast.Do_update update ->
    Ast.Do_update
      { update with
        assignments = List.map update.assignments ~f:normalize_assignment
      ; where_ = optional_condition update.where_
      }
;;

let command (command : Ast.command) =
  { command with
    Ast.assignments = List.map command.assignments ~f:normalize_assignment
  ; rows = List.map command.rows ~f:(List.map ~f:normalize_assignment)
  ; conflict = Option.map command.conflict ~f:normalize_conflict
  ; where_ = optional_condition command.where_
  }
;;

let select = normalize_select

let result_query = function
  | Ast.Select query -> Ast.Select (select query)
  | Ast.Returning returning ->
    Ast.Returning
      { command = command returning.command
      ; projection = List.map returning.projection ~f:normalize_expr
      }
;;
