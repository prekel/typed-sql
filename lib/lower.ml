open! Base

type result_query = Ast.result_query
type command = Ast.command

let has_default assignments =
  List.exists assignments ~f:(fun assignment ->
    match assignment.Ast.value with
    | Ast.Default -> true
    | Ast.Expression _ -> false)
;;

let unsupported operation dialect =
  Error (Compile_error.Unsupported_operation { operation; dialect })
;;

let comparison ~dialect comparison =
  match dialect, comparison with
  | Dialect.Sqlite, Ast.Is_distinct_from -> Ast.Sqlite_is_not
  | _, comparison -> comparison
;;

let string_function ~dialect function_ =
  match dialect, function_ with
  | Dialect.Sqlite, Ast.Length -> Ast.Sqlite_length
  | _, function_ -> function_
;;

let rec expression ~dialect = function
  | Ast.Column _ as expression -> expression
  | Ast.Param _ as expression -> expression
  | Ast.Arithmetic (operator, left, right) ->
    Ast.Arithmetic (operator, expression ~dialect left, expression ~dialect right)
  | Ast.String_function (function_, value) ->
    Ast.String_function (string_function ~dialect function_, expression ~dialect value)
  | Ast.Concat (left, right) ->
    Ast.Concat (expression ~dialect left, expression ~dialect right)
  | Ast.Case (branches, else_) ->
    Ast.Case
      ( List.map branches ~f:(fun (condition_, value) ->
          condition ~dialect condition_, expression ~dialect value)
      , expression ~dialect else_ )
  | Ast.Aggregate Ast.Count_all as value -> value
  | Ast.Aggregate (Ast.Count value) ->
    Ast.Aggregate (Ast.Count (expression ~dialect value))
  | Ast.Aggregate (Ast.Count_distinct value) ->
    Ast.Aggregate (Ast.Count_distinct (expression ~dialect value))
  | Ast.Scalar_subquery select_ -> Ast.Scalar_subquery (select ~dialect select_)
  | Ast.Current_timestamp as value -> value

and condition ~dialect = function
  | Ast.True -> Ast.True
  | Ast.False -> Ast.False
  | Ast.Compare (comparison_, left, right) ->
    Ast.Compare
      ( comparison ~dialect comparison_
      , expression ~dialect left
      , expression ~dialect right )
  | Ast.Is_null value -> Ast.Is_null (expression ~dialect value)
  | Ast.Is_not_null value -> Ast.Is_not_null (expression ~dialect value)
  | Ast.In (value, values) ->
    Ast.In (expression ~dialect value, List.map values ~f:(expression ~dialect))
  | Ast.Not_in (value, values) ->
    Ast.Not_in (expression ~dialect value, List.map values ~f:(expression ~dialect))
  | Ast.Between (value, lower, upper) ->
    Ast.Between
      (expression ~dialect value, expression ~dialect lower, expression ~dialect upper)
  | Ast.Exists select_ -> Ast.Exists (select ~dialect select_)
  | Ast.Not_exists select_ -> Ast.Not_exists (select ~dialect select_)
  | Ast.In_subquery (value, select_) ->
    Ast.In_subquery (expression ~dialect value, select ~dialect select_)
  | Ast.Not_in_subquery (value, select_) ->
    Ast.Not_in_subquery (expression ~dialect value, select ~dialect select_)
  | Ast.And conditions -> Ast.And (List.map conditions ~f:(condition ~dialect))
  | Ast.Or conditions -> Ast.Or (List.map conditions ~f:(condition ~dialect))
  | Ast.Not condition_ -> Ast.Not (condition ~dialect condition_)

and select ~dialect (select : Ast.select) =
  { select with
    Ast.projection = List.map select.projection ~f:(expression ~dialect)
  ; joins =
      List.map select.joins ~f:(fun (join : Ast.join) ->
        { join with Ast.on = condition ~dialect join.on })
  ; where_ = Option.map select.where_ ~f:(condition ~dialect)
  ; group_by = List.map select.group_by ~f:(expression ~dialect)
  ; having = Option.map select.having ~f:(condition ~dialect)
  ; order_by =
      List.map select.order_by ~f:(fun order ->
        { order with Ast.expr = expression ~dialect order.expr })
  }
;;

let assignment ~dialect (assignment : Ast.assignment) =
  let value =
    match assignment.Ast.value with
    | Ast.Default -> Ast.Default
    | Ast.Expression value -> Ast.Expression (expression ~dialect value)
  in
  { assignment with Ast.value }
;;

let lower_command ~dialect (command : Ast.command) =
  { command with
    Ast.assignments = List.map command.assignments ~f:(assignment ~dialect)
  ; rows = List.map command.rows ~f:(List.map ~f:(assignment ~dialect))
  ; where_ = Option.map command.where_ ~f:(condition ~dialect)
  }
;;

let command ~dialect command =
  match dialect, command.Ast.kind with
  | Dialect.Sqlite, Ast.Insert when List.exists command.rows ~f:has_default ->
    unsupported "INSERT DEFAULT" dialect
  | Dialect.Sqlite, Ast.Update when has_default command.assignments ->
    unsupported "UPDATE SET DEFAULT" dialect
  | _ -> Ok (lower_command ~dialect command)
;;

let result_query ~dialect query =
  match query with
  | Ast.Select select_ -> Ok (Ast.Select (select ~dialect select_))
  | Ast.Returning returning ->
    let open Result.Let_syntax in
    let%map command = command ~dialect returning.command in
    Ast.Returning
      { command; projection = List.map returning.projection ~f:(expression ~dialect) }
;;

let result_query_ast query = query
let command_ast command = command
