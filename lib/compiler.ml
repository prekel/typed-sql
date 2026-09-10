open! Base

type render_state =
  { next_parameter : int
  ; parameters_rev : Db_type.packed_value list
  }

let initial_state = { next_parameter = 0; parameters_rev = [] }

let normalize_condition condition =
  let rec normalize = function
    | Ast.True -> Ast.True
    | Ast.False -> Ast.False
    | Ast.Compare _ as condition -> condition
    | Ast.Is_null _ as condition -> condition
    | Ast.Is_not_null _ as condition -> condition
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
;;

let validate_expr ~expected_source = function
  | Ast.Param _ -> Ok ()
  | Ast.Column { source_id; _ } ->
    if Int.equal expected_source source_id then
      Ok ()
    else
      Error
        (Compile_error.Foreign_source { expected = expected_source; actual = source_id })
;;

let rec validate_condition ~expected_source = function
  | Ast.True | Ast.False -> Ok ()
  | Ast.Compare (_, left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~expected_source left in
    validate_expr ~expected_source right
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    validate_expr ~expected_source expression
  | Ast.And conditions | Ast.Or conditions ->
    validate_conditions ~expected_source conditions
  | Ast.Not condition -> validate_condition ~expected_source condition

and validate_conditions ~expected_source = function
  | [] -> Ok ()
  | condition :: rest ->
    let open Result.Let_syntax in
    let%bind () = validate_condition ~expected_source condition in
    validate_conditions ~expected_source rest
;;

let rec validate_expressions ~expected_source = function
  | [] -> Ok ()
  | expression :: rest ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~expected_source expression in
    validate_expressions ~expected_source rest
;;

let validate select =
  let expected_source = select.Ast.source.source_id in
  if List.is_empty select.projection then
    Error Compile_error.Empty_projection
  else (
    match
      select.limit
    with
    | Some value when value < 0 -> Error (Compile_error.Negative_limit value)
    | _ ->
      (match select.offset with
       | Some value when value < 0 -> Error (Compile_error.Negative_offset value)
       | _ ->
         let open Result.Let_syntax in
         let%bind () = validate_expressions ~expected_source select.projection in
         let%bind () =
           match select.where_ with
           | None -> Ok ()
           | Some condition -> validate_condition ~expected_source condition
         in
         validate_expressions
           ~expected_source
           (List.map select.order_by ~f:(fun order -> order.Ast.expr))))
;;

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

let render_expr ~alias expression state =
  match expression with
  | Ast.Column { name; _ } ->
    [ Template.Text (alias ^ "." ^ quote_identifier name) ], state
  | Ast.Param value ->
    let index = state.next_parameter in
    ( [ Template.Param index ]
    , { next_parameter = index + 1; parameters_rev = value :: state.parameters_rev } )
;;

let render_comparison = function
  | Ast.Eq -> " = "
  | Ast.Neq -> " <> "
  | Ast.Lt -> " < "
  | Ast.Lte -> " <= "
  | Ast.Gt -> " > "
  | Ast.Gte -> " >= "
  | Ast.Like -> " LIKE "
;;

let rec render_condition ~alias condition state =
  match condition with
  | Ast.True -> [ Template.Text "TRUE" ], state
  | Ast.False -> [ Template.Text "FALSE" ], state
  | Ast.Compare (comparison, left, right) ->
    let left_parts, state = render_expr ~alias left state in
    let right_parts, state = render_expr ~alias right state in
    ( [ Template.Text "(" ] @ left_parts
      @ [ Template.Text (render_comparison comparison) ]
      @ right_parts @ [ Template.Text ")" ]
    , state )
  | Ast.Is_null expression ->
    let expression, state = render_expr ~alias expression state in
    [ Template.Text "(" ] @ expression @ [ Template.Text " IS NULL)" ], state
  | Ast.Is_not_null expression ->
    let expression, state = render_expr ~alias expression state in
    [ Template.Text "(" ] @ expression @ [ Template.Text " IS NOT NULL)" ], state
  | Ast.Not condition ->
    let condition, state = render_condition ~alias condition state in
    [ Template.Text "(NOT " ] @ condition @ [ Template.Text ")" ], state
  | Ast.And conditions -> render_condition_list ~alias ~separator:" AND " conditions state
  | Ast.Or conditions -> render_condition_list ~alias ~separator:" OR " conditions state

and render_condition_list ~alias ~separator conditions state =
  let parts, state = render_conditions ~alias ~separator conditions state in
  [ Template.Text "(" ] @ parts @ [ Template.Text ")" ], state

and render_conditions ~alias ~separator conditions state =
  match conditions with
  | [] -> [], state
  | [ condition ] -> render_condition ~alias condition state
  | condition :: rest ->
    let condition, state = render_condition ~alias condition state in
    let rest, state = render_conditions ~alias ~separator rest state in
    condition @ [ Template.Text separator ] @ rest, state
;;

let rec render_expressions ~alias ~separator expressions state =
  match expressions with
  | [] -> [], state
  | [ expression ] -> render_expr ~alias expression state
  | expression :: rest ->
    let expression, state = render_expr ~alias expression state in
    let rest, state = render_expressions ~alias ~separator rest state in
    expression @ [ Template.Text separator ] @ rest, state
;;

let rec render_order_by ~alias orders state =
  match orders with
  | [] -> [], state
  | order :: rest ->
    let expression, state = render_expr ~alias order.Ast.expr state in
    let direction =
      match order.direction with
      | Ast.Asc -> " ASC"
      | Ast.Desc -> " DESC"
    in
    let current = expression @ [ Template.Text direction ] in
    (match rest with
     | [] -> current, state
     | _ ->
       let rest, state = render_order_by ~alias rest state in
       current @ [ Template.Text ", " ] @ rest, state)
;;

let render select =
  let alias = "t0" in
  let projection, state =
    render_expressions ~alias ~separator:", " select.Ast.projection initial_state
  in
  let parts =
    [ Template.Text "SELECT " ] @ projection
    @ [ Template.Text (" FROM " ^ render_source select.source ^ " AS " ^ alias) ]
  in
  let parts, state =
    match select.where_ with
    | None | Some Ast.True -> parts, state
    | Some condition ->
      let condition, state = render_condition ~alias condition state in
      parts @ [ Template.Text " WHERE " ] @ condition, state
  in
  let parts, state =
    match select.order_by with
    | [] -> parts, state
    | order_by ->
      let order_by, state = render_order_by ~alias order_by state in
      parts @ [ Template.Text " ORDER BY " ] @ order_by, state
  in
  let parts =
    match select.limit with
    | None -> parts
    | Some value -> parts @ [ Template.Text (" LIMIT " ^ Int.to_string value) ]
  in
  let parts =
    match select.offset with
    | None -> parts
    | Some value -> parts @ [ Template.Text (" OFFSET " ^ Int.to_string value) ]
  in
  Template.Private.of_parts parts, List.rev state.parameters_rev
;;

let parameter_type_names parameters =
  List.map parameters ~f:(fun (Db_type.Value (db_type, _)) -> Db_type.name db_type)
  |> String.concat ~sep:","
;;

let compile ~dialect query =
  let select = Query.Private.ast query in
  let where_ =
    Option.map select.where_ ~f:normalize_condition
    |> Option.bind ~f:(function
      | Ast.True -> None
      | condition -> Some condition)
  in
  let select = { select with where_ } in
  Result.map (validate select) ~f:(fun () ->
    let template, parameters = render select in
    let shape =
      String.concat
        [ Dialect.to_string dialect
        ; ":"
        ; Template.Private.shape_string template
        ; "|"
        ; parameter_type_names parameters
        ]
      |> Shape.Private.create
    in
    Compiled_query.Private.create
      ~dialect
      ~template
      ~parameters
      ~projection:(Query.Private.projection query)
      ~shape)
;;
