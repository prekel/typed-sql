open! Base

let validate_expr ~visible = function
  | Ast.Param _ -> Ok ()
  | Ast.Column { source_id; _ } ->
    if List.mem visible source_id ~equal:Int.equal then
      Ok ()
    else
      Error (Compile_error.Foreign_source { visible; actual = source_id })
;;

let rec validate_condition ~visible = function
  | Ast.True | Ast.False -> Ok ()
  | Ast.Compare (_, left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~visible left in
    validate_expr ~visible right
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    validate_expr ~visible expression
  | Ast.And conditions | Ast.Or conditions -> validate_conditions ~visible conditions
  | Ast.Not condition -> validate_condition ~visible condition

and validate_conditions ~visible = function
  | [] -> Ok ()
  | condition :: rest ->
    let open Result.Let_syntax in
    let%bind () = validate_condition ~visible condition in
    validate_conditions ~visible rest
;;

let rec validate_expressions ~visible = function
  | [] -> Ok ()
  | expression :: rest ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~visible expression in
    validate_expressions ~visible rest
;;

let validate_joins source_id (joins : Ast.join list) =
  let rec loop visible = function
    | [] -> Ok visible
    | (join : Ast.join) :: rest ->
      let visible = visible @ [ join.Ast.source.source_id ] in
      let open Result.Let_syntax in
      let%bind () = validate_condition ~visible join.on in
      loop visible rest
  in
  loop [ source_id ] joins
;;

let validate_select (select : Ast.select) =
  if List.is_empty select.Ast.projection then
    Error Compile_error.Empty_projection
  else if Option.exists select.limit ~f:(fun value -> value < 0) then
    Error (Compile_error.Negative_limit (Option.value_exn select.limit))
  else if Option.exists select.offset ~f:(fun value -> value < 0) then
    Error (Compile_error.Negative_offset (Option.value_exn select.offset))
  else
    let open Result.Let_syntax in
    let%bind visible = validate_joins select.source.source_id select.joins in
    let%bind () = validate_expressions ~visible select.projection in
    let%bind () =
      match select.where_ with
      | None -> Ok ()
      | Some condition -> validate_condition ~visible condition
    in
    validate_expressions
      ~visible
      (List.map select.order_by ~f:(fun order -> order.Ast.expr))
;;

let duplicate_assignment assignments =
  let rec loop seen = function
    | [] -> None
    | assignment :: rest ->
      if List.exists seen ~f:(Identifier.equal assignment.Ast.column) then
        Some assignment.column
      else
        loop (assignment.column :: seen) rest
  in
  loop [] assignments
;;

let rec validate_assignments ~source_id = function
  | [] -> Ok ()
  | assignment :: rest ->
    if not (Int.equal assignment.Ast.source_id source_id) then
      Error
        (Compile_error.Invalid_assignment_source
           { expected = source_id; actual = assignment.source_id })
    else
      let open Result.Let_syntax in
      let%bind () = validate_expr ~visible:[ source_id ] assignment.value in
      validate_assignments ~source_id rest
;;

let validate_command (command : Ast.command) =
  let empty_error =
    match command.Ast.kind, command.assignments with
    | Ast.Insert, [] -> Some (Compile_error.Empty_assignments `Insert)
    | Ast.Update, [] -> Some (Compile_error.Empty_assignments `Update)
    | Ast.Delete, _ | (Ast.Insert | Ast.Update), _ -> None
  in
  match empty_error with
  | Some error -> Error error
  | None ->
    (match duplicate_assignment command.assignments with
     | Some column -> Error (Compile_error.Duplicate_assignment column)
     | None ->
       let source_id = command.source.source_id in
       let open Result.Let_syntax in
       let%bind () = validate_assignments ~source_id command.assignments in
       (match command.where_ with
        | None -> Ok ()
        | Some condition -> validate_condition ~visible:[ source_id ] condition))
;;

let result_query = function
  | Ast.Select select -> validate_select select
  | Ast.Returning returning ->
    if List.is_empty returning.projection then
      Error Compile_error.Empty_projection
    else
      let open Result.Let_syntax in
      let%bind () = validate_command returning.command in
      validate_expressions
        ~visible:[ returning.command.source.source_id ]
        returning.projection
;;

let command = validate_command
