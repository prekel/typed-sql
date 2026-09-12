open! Base

type state =
  { next_parameter : int
  ; parameters_rev : Db_type.packed_value list
  }

let initial_state = { next_parameter = 0; parameters_rev = [] }

let quote_identifier identifier =
  let value = Identifier.to_string identifier in
  let escaped = String.substr_replace_all value ~pattern:"\"" ~with_:"\"\"" in
  "\"" ^ escaped ^ "\""
;;

let render_source source =
  let table = quote_identifier source.Ast.table in
  match source.schema with
  | None -> table
  | Some schema -> quote_identifier schema ^ "." ^ table
;;

let alias_for aliases source_id = List.Assoc.find_exn aliases source_id ~equal:Int.equal

let arithmetic_sql = function
  | Ast.Add -> " + "
  | Ast.Subtract -> " - "
  | Ast.Multiply -> " * "
  | Ast.Divide -> " / "
;;

let string_function_sql = function
  | Ast.Lower -> "LOWER"
  | Ast.Upper -> "UPPER"
  | Ast.Length -> "CHAR_LENGTH"
  | Ast.Sqlite_length -> "LENGTH"
;;

let comparison_sql = function
  | Ast.Eq -> " = "
  | Ast.Neq -> " <> "
  | Ast.Lt -> " < "
  | Ast.Lte -> " <= "
  | Ast.Gt -> " > "
  | Ast.Gte -> " >= "
  | Ast.Like -> " LIKE "
  | Ast.Is_distinct_from -> " IS DISTINCT FROM "
  | Ast.Sqlite_is_not -> " IS NOT "
;;

let aliases_for_select ~parent_aliases (select : Ast.select) =
  let sources =
    select.Ast.source :: List.map select.joins ~f:(fun (join : Ast.join) -> join.source)
  in
  let first_index = List.length parent_aliases in
  parent_aliases
  @ List.mapi sources ~f:(fun index source ->
    source.source_id, "t" ^ Int.to_string (first_index + index))
;;

let rec render_expr ~aliases expression state =
  match expression with
  | Ast.Column { source_id; name; _ } ->
    let alias = alias_for aliases source_id in
    let prefix =
      if String.is_empty alias then
        ""
      else
        alias ^ "."
    in
    [ Template.Text (prefix ^ quote_identifier name) ], state
  | Ast.Param value ->
    let index = state.next_parameter in
    ( [ Template.Param index ]
    , { next_parameter = index + 1; parameters_rev = value :: state.parameters_rev } )
  | Ast.Arithmetic (operator, left, right) ->
    let left, state = render_expr ~aliases left state in
    let right, state = render_expr ~aliases right state in
    ( [ Template.Text "(" ] @ left
      @ [ Template.Text (arithmetic_sql operator) ]
      @ right @ [ Template.Text ")" ]
    , state )
  | Ast.String_function (function_, expression) ->
    let expression, state = render_expr ~aliases expression state in
    ( [ Template.Text (string_function_sql function_ ^ "(") ]
      @ expression @ [ Template.Text ")" ]
    , state )
  | Ast.Concat (left, right) ->
    let left, state = render_expr ~aliases left state in
    let right, state = render_expr ~aliases right state in
    ( [ Template.Text "(" ] @ left @ [ Template.Text " || " ] @ right
      @ [ Template.Text ")" ]
    , state )
  | Ast.Case (branches, else_) ->
    let branches, state = render_case_branches ~aliases branches state in
    let else_, state = render_expr ~aliases else_ state in
    ( [ Template.Text "(CASE " ] @ branches @ [ Template.Text "ELSE " ] @ else_
      @ [ Template.Text " END)" ]
    , state )
  | Ast.Aggregate Ast.Count_all -> [ Template.Text "COUNT(*)" ], state
  | Ast.Aggregate (Ast.Count expression) ->
    let expression, state = render_expr ~aliases expression state in
    [ Template.Text "COUNT(" ] @ expression @ [ Template.Text ")" ], state
  | Ast.Aggregate (Ast.Count_distinct expression) ->
    let expression, state = render_expr ~aliases expression state in
    [ Template.Text "COUNT(DISTINCT " ] @ expression @ [ Template.Text ")" ], state
  | Ast.Scalar_subquery select ->
    let select, state = render_select ~parent_aliases:aliases select state in
    [ Template.Text "(" ] @ select @ [ Template.Text ")" ], state
  | Ast.Current_timestamp -> [ Template.Text "CURRENT_TIMESTAMP" ], state

and render_case_branches ~aliases branches state =
  match branches with
  | [] -> [], state
  | (condition, expression) :: rest ->
    let condition, state = render_condition ~aliases condition state in
    let expression, state = render_expr ~aliases expression state in
    let rest, state = render_case_branches ~aliases rest state in
    ( [ Template.Text "WHEN " ] @ condition @ [ Template.Text " THEN " ] @ expression
      @ [ Template.Text " " ] @ rest
    , state )

and render_condition ~aliases condition state =
  match condition with
  | Ast.True -> [ Template.Text "TRUE" ], state
  | Ast.False -> [ Template.Text "FALSE" ], state
  | Ast.Compare (comparison, left, right) ->
    let left, state = render_expr ~aliases left state in
    let right, state = render_expr ~aliases right state in
    ( [ Template.Text "(" ] @ left
      @ [ Template.Text (comparison_sql comparison) ]
      @ right @ [ Template.Text ")" ]
    , state )
  | Ast.Is_null expression ->
    let expression, state = render_expr ~aliases expression state in
    [ Template.Text "(" ] @ expression @ [ Template.Text " IS NULL)" ], state
  | Ast.Is_not_null expression ->
    let expression, state = render_expr ~aliases expression state in
    [ Template.Text "(" ] @ expression @ [ Template.Text " IS NOT NULL)" ], state
  | Ast.In (expression, values) ->
    render_membership ~aliases ~operator:" IN " expression values state
  | Ast.Not_in (expression, values) ->
    render_membership ~aliases ~operator:" NOT IN " expression values state
  | Ast.Between (expression, lower, upper) ->
    let expression, state = render_expr ~aliases expression state in
    let lower, state = render_expr ~aliases lower state in
    let upper, state = render_expr ~aliases upper state in
    ( [ Template.Text "(" ] @ expression @ [ Template.Text " BETWEEN " ] @ lower
      @ [ Template.Text " AND " ] @ upper @ [ Template.Text ")" ]
    , state )
  | Ast.Exists select -> render_exists ~aliases ~operator:"EXISTS" select state
  | Ast.Not_exists select -> render_exists ~aliases ~operator:"NOT EXISTS" select state
  | Ast.In_subquery (expression, select) ->
    render_subquery_membership ~aliases ~operator:" IN " expression select state
  | Ast.Not_in_subquery (expression, select) ->
    render_subquery_membership ~aliases ~operator:" NOT IN " expression select state
  | Ast.Not condition ->
    let condition, state = render_condition ~aliases condition state in
    [ Template.Text "(NOT " ] @ condition @ [ Template.Text ")" ], state
  | Ast.And conditions ->
    render_condition_list ~aliases ~separator:" AND " conditions state
  | Ast.Or conditions -> render_condition_list ~aliases ~separator:" OR " conditions state

and render_condition_list ~aliases ~separator conditions state =
  let parts, state = render_conditions ~aliases ~separator conditions state in
  [ Template.Text "(" ] @ parts @ [ Template.Text ")" ], state

and render_conditions ~aliases ~separator conditions state =
  match conditions with
  | [] -> [], state
  | [ condition ] -> render_condition ~aliases condition state
  | condition :: rest ->
    let condition, state = render_condition ~aliases condition state in
    let rest, state = render_conditions ~aliases ~separator rest state in
    condition @ [ Template.Text separator ] @ rest, state

and render_membership ~aliases ~operator expression values state =
  let expression, state = render_expr ~aliases expression state in
  let values, state = render_expressions ~aliases ~separator:", " values state in
  ( [ Template.Text "(" ] @ expression
    @ [ Template.Text operator; Template.Text "(" ]
    @ values @ [ Template.Text "))" ]
  , state )

and render_exists ~aliases ~operator select state =
  let select, state = render_select ~parent_aliases:aliases select state in
  [ Template.Text ("(" ^ operator ^ " (") ] @ select @ [ Template.Text "))" ], state

and render_subquery_membership ~aliases ~operator expression select state =
  let expression, state = render_expr ~aliases expression state in
  let select, state = render_select ~parent_aliases:aliases select state in
  ( [ Template.Text "(" ] @ expression
    @ [ Template.Text operator; Template.Text "(" ]
    @ select @ [ Template.Text "))" ]
  , state )

and render_expressions ~aliases ~separator expressions state =
  match expressions with
  | [] -> [], state
  | [ expression ] -> render_expr ~aliases expression state
  | expression :: rest ->
    let expression, state = render_expr ~aliases expression state in
    let rest, state = render_expressions ~aliases ~separator rest state in
    expression @ [ Template.Text separator ] @ rest, state

and render_join ~aliases (join : Ast.join) state =
  let kind =
    match join.Ast.kind with
    | Ast.Inner -> " INNER JOIN "
    | Ast.Left -> " LEFT JOIN "
  in
  let alias = alias_for aliases join.source.source_id in
  let on, state = render_condition ~aliases join.on state in
  ( [ Template.Text (kind ^ render_source join.source ^ " AS " ^ alias ^ " ON ") ] @ on
  , state )

and render_joins ~aliases joins state =
  match joins with
  | [] -> [], state
  | join :: rest ->
    let join, state = render_join ~aliases join state in
    let rest, state = render_joins ~aliases rest state in
    join @ rest, state

and render_order_by ~aliases orders state =
  match orders with
  | [] -> [], state
  | order :: rest ->
    let expression, state = render_expr ~aliases order.Ast.expr state in
    let direction =
      match order.direction with
      | Ast.Asc -> " ASC"
      | Ast.Desc -> " DESC"
    in
    let current = expression @ [ Template.Text direction ] in
    (match rest with
     | [] -> current, state
     | _ ->
       let rest, state = render_order_by ~aliases rest state in
       current @ [ Template.Text ", " ] @ rest, state)

and render_select ~parent_aliases (select : Ast.select) state =
  let aliases = aliases_for_select ~parent_aliases select in
  let projection, state =
    match select.Ast.projection with
    | [] -> [ Template.Text "1" ], state
    | projection -> render_expressions ~aliases ~separator:", " projection state
  in
  let root_alias = alias_for aliases select.source.source_id in
  let joins, state = render_joins ~aliases select.joins state in
  let parts =
    [ Template.Text
        (if select.distinct then
           "SELECT DISTINCT "
         else
           "SELECT ")
    ]
    @ projection
    @ [ Template.Text (" FROM " ^ render_source select.source ^ " AS " ^ root_alias) ]
    @ joins
  in
  let parts, state =
    match select.where_ with
    | None -> parts, state
    | Some condition ->
      let condition, state = render_condition ~aliases condition state in
      parts @ [ Template.Text " WHERE " ] @ condition, state
  in
  let parts, state =
    match select.group_by with
    | [] -> parts, state
    | expressions ->
      let expressions, state =
        render_expressions ~aliases ~separator:", " expressions state
      in
      parts @ [ Template.Text " GROUP BY " ] @ expressions, state
  in
  let parts, state =
    match select.having with
    | None -> parts, state
    | Some condition ->
      let condition, state = render_condition ~aliases condition state in
      parts @ [ Template.Text " HAVING " ] @ condition, state
  in
  let parts, state =
    match select.order_by with
    | [] -> parts, state
    | orders ->
      let orders, state = render_order_by ~aliases orders state in
      parts @ [ Template.Text " ORDER BY " ] @ orders, state
  in
  let parts =
    match select.limit with
    | None -> parts
    | Some n -> parts @ [ Template.Text (" LIMIT " ^ Int.to_string n) ]
  in
  let parts =
    match select.offset with
    | None -> parts
    | Some n -> parts @ [ Template.Text (" OFFSET " ^ Int.to_string n) ]
  in
  parts, state
;;

let render_assignment_value ~aliases value state =
  match value with
  | Ast.Expression expression -> render_expr ~aliases expression state
  | Ast.Default -> [ Template.Text "DEFAULT" ], state
;;

let render_assignment ~aliases assignment state =
  let value, state = render_assignment_value ~aliases assignment.Ast.value state in
  [ Template.Text (quote_identifier assignment.column ^ " = ") ] @ value, state
;;

let rec render_assignments ~aliases assignments state =
  match assignments with
  | [] -> [], state
  | [ assignment ] -> render_assignment ~aliases assignment state
  | assignment :: rest ->
    let assignment, state = render_assignment ~aliases assignment state in
    let rest, state = render_assignments ~aliases rest state in
    assignment @ [ Template.Text ", " ] @ rest, state
;;

let render_insert_row ~aliases ~columns assignments state =
  let values =
    List.map columns ~f:(fun column ->
      List.find_exn assignments ~f:(fun assignment ->
        Identifier.equal column assignment.Ast.column)
      |> fun assignment -> assignment.Ast.value)
  in
  let rec render_values values state =
    match values with
    | [] -> [], state
    | [ value ] -> render_assignment_value ~aliases value state
    | value :: rest ->
      let value, state = render_assignment_value ~aliases value state in
      let rest, state = render_values rest state in
      value @ [ Template.Text ", " ] @ rest, state
  in
  let values, state = render_values values state in
  [ Template.Text "(" ] @ values @ [ Template.Text ")" ], state
;;

let rec render_insert_rows ~aliases ~columns rows state =
  match rows with
  | [] -> [], state
  | [ row ] -> render_insert_row ~aliases ~columns row state
  | row :: rest ->
    let row, state = render_insert_row ~aliases ~columns row state in
    let rest, state = render_insert_rows ~aliases ~columns rest state in
    row @ [ Template.Text ", " ] @ rest, state
;;

let aliases_for_command (command : Ast.command) =
  match command.kind, command.from with
  | Ast.Update, _ :: _ ->
    let sources = command.source :: command.from in
    List.mapi sources ~f:(fun index source ->
      source.Ast.source_id, "t" ^ Int.to_string index)
  | _ -> [ command.source.source_id, "" ]
;;

let render_from_sources ~aliases sources =
  List.map sources ~f:(fun (source : Ast.source) ->
    let alias = alias_for aliases source.Ast.source_id in
    render_source source ^ " AS " ^ alias)
  |> String.concat ~sep:", "
;;

let render_command_ast (command : Ast.command) state =
  let aliases = aliases_for_command command in
  match command.kind with
  | Ast.Insert ->
    let first_row = List.hd_exn command.rows in
    let columns = List.map first_row ~f:(fun assignment -> assignment.Ast.column) in
    let rendered_columns =
      List.map columns ~f:quote_identifier |> String.concat ~sep:", "
    in
    let rows, state = render_insert_rows ~aliases ~columns command.rows state in
    let parts =
      [ Template.Text
          ("INSERT INTO "
           ^ render_source command.source
           ^ " ("
           ^ rendered_columns
           ^ ") VALUES ")
      ]
      @ rows
    in
    let parts =
      match command.conflict with
      | None -> parts
      | Some Ast.Do_nothing -> parts @ [ Template.Text " ON CONFLICT DO NOTHING" ]
    in
    parts, state
  | Ast.Update ->
    let assignments, state = render_assignments ~aliases command.assignments state in
    let target_alias = alias_for aliases command.source.source_id in
    let target_alias =
      if String.is_empty target_alias then
        ""
      else
        " AS " ^ target_alias
    in
    let parts =
      [ Template.Text ("UPDATE " ^ render_source command.source ^ target_alias ^ " SET ")
      ]
      @ assignments
    in
    let parts =
      match command.from with
      | [] -> parts
      | sources ->
        parts @ [ Template.Text (" FROM " ^ render_from_sources ~aliases sources) ]
    in
    (match command.where_ with
     | None -> parts, state
     | Some condition ->
       let condition, state = render_condition ~aliases condition state in
       parts @ [ Template.Text " WHERE " ] @ condition, state)
  | Ast.Delete ->
    let parts = [ Template.Text ("DELETE FROM " ^ render_source command.source) ] in
    (match command.where_ with
     | None -> parts, state
     | Some condition ->
       let condition, state = render_condition ~aliases condition state in
       parts @ [ Template.Text " WHERE " ] @ condition, state)
;;

let finish (parts, state) = Template.of_parts parts, List.rev state.parameters_rev

let result_query query =
  match Lower.result_query_ast query with
  | Ast.Select select -> finish (render_select ~parent_aliases:[] select initial_state)
  | Ast.Returning returning ->
    let parts, state = render_command_ast returning.command initial_state in
    let aliases = [ returning.command.source.source_id, "" ] in
    let projection, state =
      render_expressions ~aliases ~separator:", " returning.projection state
    in
    finish (parts @ [ Template.Text " RETURNING " ] @ projection, state)
;;

let command command =
  finish (render_command_ast (Lower.command_ast command) initial_state)
;;
