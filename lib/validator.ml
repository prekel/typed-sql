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

let rec validate_assignments ~source_id ~visible = function
  | [] -> Ok ()
  | assignment :: rest ->
    if not (Int.equal assignment.Ast.source_id source_id) then
      Error
        (Compile_error.Invalid_assignment_source
           { expected = source_id; actual = assignment.source_id })
    else
      let open Result.Let_syntax in
      let%bind () =
        match assignment.value with
        | Ast.Default -> Ok ()
        | Ast.Expression expression -> validate_expr ~visible expression
      in
      validate_assignments ~source_id ~visible rest
;;

let columns assignments =
  List.map assignments ~f:(fun assignment -> assignment.Ast.column)
;;

let same_columns left right =
  List.length left = List.length right
  && List.for_all left ~f:(fun column -> List.exists right ~f:(Identifier.equal column))
;;

let validate_insert_rows ~source_id rows =
  match rows with
  | [] | [ [] ] -> Error (Compile_error.Empty_assignments `Insert)
  | first :: rest ->
    let expected = columns first in
    let validate_row index assignments =
      if List.is_empty assignments then
        Error (Compile_error.Empty_insert_row index)
      else (
        match
          duplicate_assignment assignments
        with
        | Some column -> Error (Compile_error.Duplicate_assignment column)
        | None ->
          let actual = columns assignments in
          if not (same_columns expected actual) then
            Error
              (Compile_error.Mismatched_insert_columns { row = index; expected; actual })
          else
            validate_assignments ~source_id ~visible:[ source_id ] assignments)
    in
    let open Result.Let_syntax in
    let%bind () = validate_row 1 first in
    List.foldi rest ~init:(Ok ()) ~f:(fun index result assignments ->
      let%bind () = result in
      validate_row (index + 2) assignments)
;;

let validate_command (command : Ast.command) =
  match command.Ast.kind with
  | Ast.Insert -> validate_insert_rows ~source_id:command.source.source_id command.rows
  | Ast.Update ->
    if List.is_empty command.assignments then
      Error (Compile_error.Empty_assignments `Update)
    else (
      match
        duplicate_assignment command.assignments
      with
      | Some column -> Error (Compile_error.Duplicate_assignment column)
      | None ->
        let source_id = command.source.source_id in
        let visible =
          source_id :: List.map command.from ~f:(fun source -> source.Ast.source_id)
        in
        let open Result.Let_syntax in
        let%bind () = validate_assignments ~source_id ~visible command.assignments in
        (match command.where_ with
         | None -> Ok ()
         | Some condition -> validate_condition ~visible condition))
  | Ast.Delete ->
    (match command.where_ with
     | None -> Ok ()
     | Some condition ->
       validate_condition ~visible:[ command.source.source_id ] condition)
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
