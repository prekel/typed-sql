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

let render_expr ~aliases expression state =
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
;;

let comparison_sql = function
  | Ast.Eq -> " = "
  | Ast.Neq -> " <> "
  | Ast.Lt -> " < "
  | Ast.Lte -> " <= "
  | Ast.Gt -> " > "
  | Ast.Gte -> " >= "
  | Ast.Like -> " LIKE "
;;

let rec render_condition ~aliases condition state =
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
;;

let rec render_expressions ~aliases ~separator expressions state =
  match expressions with
  | [] -> [], state
  | [ expression ] -> render_expr ~aliases expression state
  | expression :: rest ->
    let expression, state = render_expr ~aliases expression state in
    let rest, state = render_expressions ~aliases ~separator rest state in
    expression @ [ Template.Text separator ] @ rest, state
;;

let aliases_for_select (select : Ast.select) =
  let sources =
    select.Ast.source :: List.map select.joins ~f:(fun (join : Ast.join) -> join.source)
  in
  List.mapi sources ~f:(fun index source -> source.source_id, "t" ^ Int.to_string index)
;;

let render_join ~aliases (join : Ast.join) state =
  let kind =
    match join.Ast.kind with
    | Ast.Inner -> " INNER JOIN "
    | Ast.Left -> " LEFT JOIN "
  in
  let alias = alias_for aliases join.source.source_id in
  let on, state = render_condition ~aliases join.on state in
  ( [ Template.Text (kind ^ render_source join.source ^ " AS " ^ alias ^ " ON ") ] @ on
  , state )
;;

let rec render_joins ~aliases joins state =
  match joins with
  | [] -> [], state
  | join :: rest ->
    let join, state = render_join ~aliases join state in
    let rest, state = render_joins ~aliases rest state in
    join @ rest, state
;;

let rec render_order_by ~aliases orders state =
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
;;

let render_select (select : Ast.select) =
  let aliases = aliases_for_select select in
  let projection, state =
    render_expressions ~aliases ~separator:", " select.Ast.projection initial_state
  in
  let root_alias = alias_for aliases select.source.source_id in
  let joins, state = render_joins ~aliases select.joins state in
  let parts =
    [ Template.Text "SELECT " ] @ projection
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

let render_assignment ~aliases assignment state =
  let value, state = render_expr ~aliases assignment.Ast.value state in
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

let render_command_ast (command : Ast.command) state =
  let aliases = [ command.Ast.source.source_id, "" ] in
  match command.kind with
  | Ast.Insert ->
    let columns =
      List.map command.assignments ~f:(fun a -> quote_identifier a.Ast.column)
      |> String.concat ~sep:", "
    in
    let values, state =
      render_expressions
        ~aliases
        ~separator:", "
        (List.map command.assignments ~f:(fun a -> a.Ast.value))
        state
    in
    ( [ Template.Text
          ("INSERT INTO " ^ render_source command.source ^ " (" ^ columns ^ ") VALUES (")
      ]
      @ values @ [ Template.Text ")" ]
    , state )
  | Ast.Update ->
    let assignments, state = render_assignments ~aliases command.assignments state in
    let parts =
      [ Template.Text ("UPDATE " ^ render_source command.source ^ " SET ") ] @ assignments
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
  | Ast.Select select -> finish (render_select select)
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
