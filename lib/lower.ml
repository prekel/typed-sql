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
  | Ast.Coalesce (left, right) ->
    Ast.Coalesce (expression ~dialect left, expression ~dialect right)
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
  | Ast.Aggregate (Ast.Sum_int value) ->
    Ast.Aggregate (Ast.Sum_int (expression ~dialect value))
  | Ast.Aggregate (Ast.Sum_float value) ->
    Ast.Aggregate (Ast.Sum_float (expression ~dialect value))
  | Ast.Aggregate (Ast.Sum_int64 value) ->
    Ast.Aggregate (Ast.Sum_int64 (expression ~dialect value))
  | Ast.Aggregate (Ast.Sum_numeric value) ->
    Ast.Aggregate (Ast.Sum_numeric (expression ~dialect value))
  | Ast.Aggregate (Ast.Min value) -> Ast.Aggregate (Ast.Min (expression ~dialect value))
  | Ast.Aggregate (Ast.Max value) -> Ast.Aggregate (Ast.Max (expression ~dialect value))
  | Ast.Aggregate (Ast.String_agg string_agg) ->
    Ast.Aggregate
      (Ast.String_agg
         { value = expression ~dialect string_agg.value
         ; delimiter = expression ~dialect string_agg.delimiter
         ; order_by =
             List.map string_agg.order_by ~f:(fun order ->
               { order with Ast.expr = expression ~dialect order.expr })
         })
  | Ast.Aggregate (Ast.Multiset_agg multiset) ->
    Ast.Aggregate
      (Ast.Multiset_agg
         { multiset with
           Ast.fields = List.map multiset.fields ~f:(expression ~dialect)
         ; filter = Option.map multiset.filter ~f:(condition ~dialect)
         ; order_by =
             List.map multiset.order_by ~f:(fun order ->
               { order with Ast.expr = expression ~dialect order.expr })
         })
  | Ast.Scalar_subquery select_ -> Ast.Scalar_subquery (select ~dialect select_)
  | Ast.Multiset_subquery multiset ->
    Ast.Multiset_subquery
      { multiset with Ast.query = select_query ~dialect multiset.query }
  | Ast.Exists_expr select_ -> Ast.Exists_expr (select ~dialect select_)
  | Ast.Current_timestamp as value -> value

and condition ~dialect = function
  | Ast.True -> Ast.True
  | Ast.False -> Ast.False
  | Ast.Compare (comparison_, left, right) ->
    Ast.Compare
      ( comparison ~dialect comparison_
      , expression ~dialect left
      , expression ~dialect right )
  | Ast.Equals_any (left, right) ->
    Ast.Equals_any (expression ~dialect left, expression ~dialect right)
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
    Ast.ctes = List.map select.ctes ~f:(cte ~dialect)
  ; source = source ~dialect select.source
  ; projection = List.map select.projection ~f:(expression ~dialect)
  ; joins =
      List.map select.joins ~f:(fun (join : Ast.join) ->
        { join with
          Ast.source = source ~dialect join.source
        ; on = condition ~dialect join.on
        })
  ; where_ = Option.map select.where_ ~f:(condition ~dialect)
  ; group_by = List.map select.group_by ~f:(expression ~dialect)
  ; having = Option.map select.having ~f:(condition ~dialect)
  ; order_by =
      List.map select.order_by ~f:(fun order ->
        { order with Ast.expr = expression ~dialect order.expr })
  }

and select_query ~dialect = function
  | Ast.Simple select_ -> Ast.Simple (select ~dialect select_)
  | Ast.Source_free source_free ->
    Ast.Source_free
      { ctes = List.map source_free.ctes ~f:(cte ~dialect)
      ; expression = expression ~dialect source_free.expression
      }
  | Ast.Compound compound ->
    Ast.Compound
      { compound with
        Ast.ctes = List.map compound.ctes ~f:(cte ~dialect)
      ; left = select_query ~dialect compound.left
      ; right = select_query ~dialect compound.right
      }

and relation ~dialect (relation : Ast.relation) =
  { relation with
    Ast.query = select_query ~dialect relation.query
  ; columns = List.map relation.columns ~f:(expression ~dialect)
  }

and source ~dialect (source : Ast.source) =
  let kind =
    match source.Ast.kind with
    | (Ast.Table _ | Ast.Cte _) as kind -> kind
    | Ast.Derived relation_ -> Ast.Derived (relation ~dialect relation_)
    | Ast.Values values ->
      Ast.Values
        { values with
          Ast.rows =
            List.map values.rows ~f:(fun row ->
              { row with
                Ast.expressions = List.map row.expressions ~f:(expression ~dialect)
              })
        }
  in
  { source with Ast.kind }

and cte ~dialect (cte : Ast.cte) =
  let body =
    match cte.Ast.body with
    | Ast.Select_body query -> Ast.Select_body (select_query ~dialect query)
    | Ast.Recursive_body recursive ->
      Ast.Recursive_body
        { recursive with
          anchor = relation ~dialect recursive.anchor
        ; step = relation ~dialect recursive.step
        }
    | Ast.Returning_body returning ->
      Ast.Returning_body (lower_returning ~dialect returning)
    | Ast.Command_body command -> Ast.Command_body (lower_command ~dialect command)
  in
  { cte with Ast.columns = List.map cte.columns ~f:(expression ~dialect); body }

and assignment ~dialect (assignment : Ast.assignment) =
  let value =
    match assignment.Ast.value with
    | Ast.Default -> Ast.Default
    | Ast.Expression value -> Ast.Expression (expression ~dialect value)
  in
  { assignment with Ast.value }

and conflict ~dialect = function
  | Ast.Do_nothing _ as conflict -> conflict
  | Ast.Do_update update ->
    Ast.Do_update
      { update with
        assignments = List.map update.assignments ~f:(assignment ~dialect)
      ; where_ = Option.map update.where_ ~f:(condition ~dialect)
      }

and insert_input ~dialect = function
  | Ast.Rows rows -> Ast.Rows (List.map rows ~f:(List.map ~f:(assignment ~dialect)))
  | Ast.Select_rows selected ->
    Ast.Select_rows { selected with query = select_query ~dialect selected.query }
  | Ast.Mixed_sources -> Ast.Mixed_sources

and lower_command ~dialect (command : Ast.command) =
  { command with
    Ast.ctes = List.map command.ctes ~f:(cte ~dialect)
  ; source = source ~dialect command.source
  ; from = List.map command.from ~f:(source ~dialect)
  ; assignments = List.map command.assignments ~f:(assignment ~dialect)
  ; insert_input = Option.map command.insert_input ~f:(insert_input ~dialect)
  ; conflict = Option.map command.conflict ~f:(conflict ~dialect)
  ; where_ = Option.map command.where_ ~f:(condition ~dialect)
  }

and lower_returning ~dialect (returning : Ast.returning) =
  { Ast.command = lower_command ~dialect returning.Ast.command
  ; projection = List.map returning.projection ~f:(expression ~dialect)
  }
;;

let rec expression_has_unsupported_having ~dialect = function
  | Ast.Column _ | Ast.Param _ | Ast.Aggregate Ast.Count_all | Ast.Current_timestamp ->
    false
  | Ast.Arithmetic (_, left, right) | Ast.Concat (left, right) | Ast.Coalesce (left, right)
    ->
    expression_has_unsupported_having ~dialect left
    || expression_has_unsupported_having ~dialect right
  | Ast.String_function (_, value)
  | Ast.Aggregate
      ( Ast.Count value
      | Ast.Count_distinct value
      | Ast.Sum_int value
      | Ast.Sum_float value
      | Ast.Sum_int64 value
      | Ast.Sum_numeric value
      | Ast.Min value
      | Ast.Max value ) -> expression_has_unsupported_having ~dialect value
  | Ast.Aggregate (Ast.String_agg { value; delimiter; order_by }) ->
    expression_has_unsupported_having ~dialect value
    || expression_has_unsupported_having ~dialect delimiter
    || List.exists order_by ~f:(fun order ->
      expression_has_unsupported_having ~dialect order.Ast.expr)
  | Ast.Aggregate (Ast.Multiset_agg multiset) ->
    List.exists multiset.fields ~f:(expression_has_unsupported_having ~dialect)
    || Option.value_map
         multiset.filter
         ~default:false
         ~f:(condition_has_unsupported_having ~dialect)
    || List.exists multiset.order_by ~f:(fun order ->
      expression_has_unsupported_having ~dialect order.Ast.expr)
  | Ast.Case (branches, else_) ->
    expression_has_unsupported_having ~dialect else_
    || List.exists branches ~f:(fun (condition_, value) ->
      condition_has_unsupported_having ~dialect condition_
      || expression_has_unsupported_having ~dialect value)
  | Ast.Scalar_subquery select_ -> select_has_unsupported_having ~dialect select_
  | Ast.Multiset_subquery multiset ->
    select_query_has_unsupported_having ~dialect multiset.query
  | Ast.Exists_expr select_ -> select_has_unsupported_having ~dialect select_

and condition_has_unsupported_having ~dialect = function
  | Ast.True | Ast.False -> false
  | Ast.Compare (_, left, right) | Ast.Equals_any (left, right) ->
    expression_has_unsupported_having ~dialect left
    || expression_has_unsupported_having ~dialect right
  | Ast.Is_null value | Ast.Is_not_null value ->
    expression_has_unsupported_having ~dialect value
  | Ast.In (value, values) | Ast.Not_in (value, values) ->
    expression_has_unsupported_having ~dialect value
    || List.exists values ~f:(expression_has_unsupported_having ~dialect)
  | Ast.Between (value, lower, upper) ->
    List.exists [ value; lower; upper ] ~f:(expression_has_unsupported_having ~dialect)
  | Ast.Exists select_ | Ast.Not_exists select_ ->
    select_has_unsupported_having ~dialect select_
  | Ast.In_subquery (value, select_) | Ast.Not_in_subquery (value, select_) ->
    expression_has_unsupported_having ~dialect value
    || select_has_unsupported_having ~dialect select_
  | Ast.And conditions | Ast.Or conditions ->
    List.exists conditions ~f:(condition_has_unsupported_having ~dialect)
  | Ast.Not condition_ -> condition_has_unsupported_having ~dialect condition_

and select_has_unsupported_having ~dialect (select : Ast.select) =
  let this_select =
    match dialect with
    | Dialect.Sqlite ->
      Option.is_some select.having
      && List.is_empty select.group_by
      && not (Aggregate_scope.projection_has_local_aggregate select)
    | Dialect.Postgresql -> false
  in
  this_select
  || List.exists select.projection ~f:(expression_has_unsupported_having ~dialect)
  || List.exists select.joins ~f:(fun join ->
    condition_has_unsupported_having ~dialect join.on)
  || Option.value_map
       select.where_
       ~default:false
       ~f:(condition_has_unsupported_having ~dialect)
  || List.exists select.group_by ~f:(expression_has_unsupported_having ~dialect)
  || Option.value_map
       select.having
       ~default:false
       ~f:(condition_has_unsupported_having ~dialect)
  || List.exists select.order_by ~f:(fun order ->
    expression_has_unsupported_having ~dialect order.expr)
  || source_has_unsupported_having ~dialect select.source
  || List.exists select.joins ~f:(fun join ->
    source_has_unsupported_having ~dialect join.Ast.source)
  || List.exists select.ctes ~f:(cte_has_unsupported_having ~dialect)

and select_query_has_unsupported_having ~dialect = function
  | Ast.Simple select -> select_has_unsupported_having ~dialect select
  | Ast.Source_free source_free ->
    expression_has_unsupported_having ~dialect source_free.expression
    || List.exists source_free.ctes ~f:(cte_has_unsupported_having ~dialect)
  | Ast.Compound compound ->
    List.exists compound.ctes ~f:(cte_has_unsupported_having ~dialect)
    || select_query_has_unsupported_having ~dialect compound.left
    || select_query_has_unsupported_having ~dialect compound.right

and source_has_unsupported_having ~dialect source =
  match source.Ast.kind with
  | Ast.Table _ | Ast.Cte _ -> false
  | Ast.Derived relation -> select_query_has_unsupported_having ~dialect relation.query
  | Ast.Values values ->
    List.exists values.rows ~f:(fun row ->
      List.exists row.Ast.expressions ~f:(expression_has_unsupported_having ~dialect))

and cte_has_unsupported_having ~dialect cte =
  match cte.Ast.body with
  | Ast.Select_body query -> select_query_has_unsupported_having ~dialect query
  | Ast.Recursive_body { anchor; step; _ } ->
    select_query_has_unsupported_having ~dialect anchor.query
    || select_query_has_unsupported_having ~dialect step.query
  | Ast.Returning_body returning ->
    command_has_unsupported_having ~dialect returning.command
    || List.exists returning.projection ~f:(expression_has_unsupported_having ~dialect)
  | Ast.Command_body command -> command_has_unsupported_having ~dialect command

and assignment_has_unsupported_having ~dialect assignment =
  match assignment.Ast.value with
  | Ast.Default -> false
  | Ast.Expression expression -> expression_has_unsupported_having ~dialect expression

and command_has_unsupported_having ~dialect command =
  List.exists command.Ast.assignments ~f:(assignment_has_unsupported_having ~dialect)
  || Option.value_map command.insert_input ~default:false ~f:(function
    | Ast.Rows rows ->
      List.exists rows ~f:(fun row ->
        List.exists row ~f:(assignment_has_unsupported_having ~dialect))
    | Ast.Select_rows selected ->
      select_query_has_unsupported_having ~dialect selected.query
    | Ast.Mixed_sources -> false)
  || Option.value_map command.conflict ~default:false ~f:(function
    | Ast.Do_nothing _ -> false
    | Ast.Do_update update ->
      List.exists update.assignments ~f:(assignment_has_unsupported_having ~dialect)
      || Option.value_map
           update.where_
           ~default:false
           ~f:(condition_has_unsupported_having ~dialect))
  || Option.value_map
       command.where_
       ~default:false
       ~f:(condition_has_unsupported_having ~dialect)
  || List.exists command.ctes ~f:(cte_has_unsupported_having ~dialect)
;;

let first_unsupported values = List.find_map values ~f:Fn.id

let rec sqlite_unsupported_expression = function
  | Ast.Column { db_type = Db_type.Pack db_type; _ } ->
    Db_type.sqlite_unsupported_type db_type
  | Ast.Param (Ast.Value (Db_type.Value (db_type, _))) ->
    Db_type.sqlite_unsupported_type db_type
  | Ast.Param (Ast.Slot { db_type = Db_type.Pack db_type; _ }) ->
    Db_type.sqlite_unsupported_type db_type
  | Ast.Aggregate Ast.Count_all | Ast.Current_timestamp -> None
  | Ast.Arithmetic (_, left, right) | Ast.Concat (left, right) | Ast.Coalesce (left, right)
    ->
    first_unsupported
      [ sqlite_unsupported_expression left; sqlite_unsupported_expression right ]
  | Ast.String_function (_, expression)
  | Ast.Aggregate
      ( Ast.Count expression
      | Ast.Count_distinct expression
      | Ast.Sum_int expression
      | Ast.Sum_float expression
      | Ast.Min expression
      | Ast.Max expression ) -> sqlite_unsupported_expression expression
  | Ast.Aggregate (Ast.Sum_int64 _ | Ast.Sum_numeric _) -> Some "numeric aggregate"
  | Ast.Aggregate (Ast.String_agg _) -> Some "PostgreSQL string_agg aggregate"
  | Ast.Aggregate (Ast.Multiset_agg multiset) ->
    first_unsupported
      (List.map multiset.fields ~f:sqlite_unsupported_expression
       @ List.map multiset.order_by ~f:(fun order ->
         sqlite_unsupported_expression order.Ast.expr)
       @ Option.value_map multiset.filter ~default:[] ~f:(fun filter ->
         [ sqlite_unsupported_condition filter ]))
  | Ast.Case (branches, else_) ->
    List.concat_map branches ~f:(fun (condition, expression) ->
      [ sqlite_unsupported_condition condition; sqlite_unsupported_expression expression ])
    |> fun branches -> first_unsupported (sqlite_unsupported_expression else_ :: branches)
  | Ast.Scalar_subquery select -> sqlite_unsupported_select select
  | Ast.Multiset_subquery multiset -> sqlite_unsupported_query multiset.query
  | Ast.Exists_expr select -> sqlite_unsupported_select select

and sqlite_unsupported_condition = function
  | Ast.True | Ast.False -> None
  | Ast.Compare (_, left, right) ->
    first_unsupported
      [ sqlite_unsupported_expression left; sqlite_unsupported_expression right ]
  | Ast.Equals_any _ -> Some "PostgreSQL = ANY"
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    sqlite_unsupported_expression expression
  | Ast.In (expression, values) | Ast.Not_in (expression, values) ->
    first_unsupported
      (sqlite_unsupported_expression expression
       :: List.map values ~f:sqlite_unsupported_expression)
  | Ast.Between (expression, lower, upper) ->
    first_unsupported
      [ sqlite_unsupported_expression expression
      ; sqlite_unsupported_expression lower
      ; sqlite_unsupported_expression upper
      ]
  | Ast.Exists select | Ast.Not_exists select -> sqlite_unsupported_select select
  | Ast.In_subquery (expression, select) | Ast.Not_in_subquery (expression, select) ->
    first_unsupported
      [ sqlite_unsupported_expression expression; sqlite_unsupported_select select ]
  | Ast.And conditions | Ast.Or conditions ->
    List.map conditions ~f:sqlite_unsupported_condition |> first_unsupported
  | Ast.Not condition -> sqlite_unsupported_condition condition

and sqlite_unsupported_select (select : Ast.select) =
  first_unsupported
    [ List.find_map select.ctes ~f:sqlite_unsupported_cte
    ; sqlite_unsupported_source select.source
    ; List.find_map select.joins ~f:(fun join ->
        first_unsupported
          [ sqlite_unsupported_source join.Ast.source
          ; sqlite_unsupported_condition join.Ast.on
          ])
    ; List.find_map select.projection ~f:sqlite_unsupported_expression
    ; Option.bind select.where_ ~f:sqlite_unsupported_condition
    ; List.find_map select.group_by ~f:sqlite_unsupported_expression
    ; Option.bind select.having ~f:sqlite_unsupported_condition
    ; List.find_map select.order_by ~f:(fun order ->
        sqlite_unsupported_expression order.Ast.expr)
    ; (match select.limit with
       | Some (Ast.Fetch_with_ties _) -> Some "FETCH FIRST WITH TIES"
       | None | Some (Ast.Limit _) -> None)
    ; Option.map select.locking ~f:(fun _ -> "FOR UPDATE")
    ]

and sqlite_unsupported_query = function
  | Ast.Simple select -> sqlite_unsupported_select select
  | Ast.Source_free source_free ->
    first_unsupported
      [ List.find_map source_free.ctes ~f:sqlite_unsupported_cte
      ; sqlite_unsupported_expression source_free.expression
      ]
  | Ast.Compound compound ->
    let operator =
      match compound.operator with
      | Ast.Intersect_all -> Some "INTERSECT ALL"
      | Ast.Except_all -> Some "EXCEPT ALL"
      | Ast.Union | Ast.Union_all | Ast.Intersect | Ast.Except -> None
    in
    first_unsupported
      [ operator
      ; List.find_map compound.ctes ~f:sqlite_unsupported_cte
      ; sqlite_unsupported_query compound.left
      ; sqlite_unsupported_query compound.right
      ]

and sqlite_unsupported_relation (relation : Ast.relation) =
  first_unsupported
    [ List.find_map relation.Ast.columns ~f:sqlite_unsupported_expression
    ; sqlite_unsupported_query relation.query
    ]

and sqlite_unsupported_source source =
  match source.Ast.kind with
  | Ast.Table _ | Ast.Cte _ -> None
  | Ast.Derived relation -> sqlite_unsupported_relation relation
  | Ast.Values values ->
    List.find_map values.rows ~f:(fun row ->
      List.find_map row.Ast.expressions ~f:sqlite_unsupported_expression)

and sqlite_unsupported_cte cte =
  match cte.Ast.body with
  | Ast.Returning_body _ | Ast.Command_body _ -> Some "data-modifying CTE"
  | Ast.Select_body query -> sqlite_unsupported_query query
  | Ast.Recursive_body { anchor; step; _ } ->
    first_unsupported
      [ sqlite_unsupported_relation anchor; sqlite_unsupported_relation step ]

and sqlite_unsupported_assignment assignment =
  match assignment.Ast.value with
  | Ast.Default -> None
  | Ast.Expression expression -> sqlite_unsupported_expression expression

and sqlite_unsupported_conflict = function
  | Ast.Do_nothing _ -> None
  | Ast.Do_update update ->
    first_unsupported
      [ List.find_map update.assignments ~f:sqlite_unsupported_assignment
      ; Option.bind update.where_ ~f:sqlite_unsupported_condition
      ]

and sqlite_unsupported_command (command : Ast.command) =
  first_unsupported
    [ List.find_map command.Ast.ctes ~f:sqlite_unsupported_cte
    ; sqlite_unsupported_source command.source
    ; List.find_map command.from ~f:sqlite_unsupported_source
    ; List.find_map command.assignments ~f:sqlite_unsupported_assignment
    ; Option.bind command.insert_input ~f:(function
        | Ast.Rows rows ->
          List.find_map rows ~f:(fun row ->
            List.find_map row ~f:sqlite_unsupported_assignment)
        | Ast.Select_rows selected -> sqlite_unsupported_query selected.query
        | Ast.Mixed_sources -> None)
    ; Option.bind command.conflict ~f:sqlite_unsupported_conflict
    ; Option.bind command.where_ ~f:sqlite_unsupported_condition
    ]

and sqlite_unsupported_returning returning =
  first_unsupported
    [ sqlite_unsupported_command returning.Ast.command
    ; List.find_map returning.projection ~f:sqlite_unsupported_expression
    ]
;;

let command ~dialect command =
  match dialect, sqlite_unsupported_command command, command.Ast.kind with
  | Dialect.Sqlite, Some operation, _ -> unsupported operation dialect
  | Dialect.Sqlite, None, _ when command_has_unsupported_having ~dialect command ->
    unsupported "HAVING without GROUP BY or an aggregate projection" dialect
  | Dialect.Sqlite, None, Ast.Insert
    when Option.value_map command.insert_input ~default:false ~f:(function
           | Ast.Rows rows -> List.exists rows ~f:has_default
           | Ast.Select_rows _ | Ast.Mixed_sources -> false) ->
    unsupported "INSERT DEFAULT" dialect
  | Dialect.Sqlite, None, Ast.Update when has_default command.assignments ->
    unsupported "UPDATE SET DEFAULT" dialect
  | Dialect.Sqlite, None, Ast.Insert
    when Option.value_map command.conflict ~default:false ~f:(function
           | Ast.Do_nothing _ -> false
           | Ast.Do_update update -> has_default update.assignments) ->
    unsupported "ON CONFLICT DO UPDATE SET DEFAULT" dialect
  | _ -> Ok (lower_command ~dialect command)
;;

let result_query ~dialect query =
  let sqlite =
    match dialect with
    | Dialect.Sqlite -> true
    | Dialect.Postgresql -> false
  in
  match query with
  | Ast.Select query when sqlite && Option.is_some (sqlite_unsupported_query query) ->
    unsupported (Option.value_exn (sqlite_unsupported_query query)) dialect
  | Ast.Select query when select_query_has_unsupported_having ~dialect query ->
    unsupported "HAVING without GROUP BY or an aggregate projection" dialect
  | Ast.Select query -> Ok (Ast.Select (select_query ~dialect query))
  | Ast.Returning returning
    when sqlite && Option.is_some (sqlite_unsupported_returning returning) ->
    unsupported (Option.value_exn (sqlite_unsupported_returning returning)) dialect
  | Ast.Returning returning
    when List.exists returning.projection ~f:(expression_has_unsupported_having ~dialect)
    -> unsupported "HAVING without GROUP BY or an aggregate projection" dialect
  | Ast.Returning returning ->
    let open Result.Let_syntax in
    let%map command = command ~dialect returning.command in
    Ast.Returning
      { command; projection = List.map returning.projection ~f:(expression ~dialect) }
;;

let result_query_ast query = query
let command_ast command = command
