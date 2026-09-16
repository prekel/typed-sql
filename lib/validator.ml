open! Base

let rec validate_expr ~validate_subquery ~visible = function
  | Ast.Param _ -> Ok ()
  | Ast.Column { source_id; _ } ->
    if List.mem visible source_id ~equal:Int.equal then
      Ok ()
    else
      Error (Compile_error.Foreign_source { visible; actual = source_id })
  | Ast.Arithmetic (_, left, right) | Ast.Concat (left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible left in
    validate_expr ~validate_subquery ~visible right
  | Ast.String_function (_, expression) ->
    validate_expr ~validate_subquery ~visible expression
  | Ast.Case (branches, else_) ->
    let open Result.Let_syntax in
    let%bind () =
      List.fold branches ~init:(Ok ()) ~f:(fun result (condition, expression) ->
        let%bind () = result in
        let%bind () = validate_condition ~validate_subquery ~visible condition in
        validate_expr ~validate_subquery ~visible expression)
    in
    validate_expr ~validate_subquery ~visible else_
  | Ast.Aggregate Ast.Count_all -> Ok ()
  | Ast.Aggregate (Ast.Count expression | Ast.Count_distinct expression) ->
    validate_expr ~validate_subquery ~visible expression
  | Ast.Scalar_subquery select ->
    let open Result.Let_syntax in
    let%bind () = validate_subquery ~outer_visible:visible ~allow_empty:false select in
    if Aggregate_scope.at_most_one select then
      Ok ()
    else
      Error Compile_error.Scalar_subquery_may_return_many_rows
  | Ast.Current_timestamp -> Ok ()

and validate_condition ~validate_subquery ~visible = function
  | Ast.True | Ast.False -> Ok ()
  | Ast.Compare (_, left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible left in
    validate_expr ~validate_subquery ~visible right
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    validate_expr ~validate_subquery ~visible expression
  | Ast.In (expression, values) | Ast.Not_in (expression, values) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible expression in
    validate_expressions ~validate_subquery ~visible values
  | Ast.Between (expression, lower, upper) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible expression in
    let%bind () = validate_expr ~validate_subquery ~visible lower in
    validate_expr ~validate_subquery ~visible upper
  | Ast.Exists select | Ast.Not_exists select ->
    validate_subquery ~outer_visible:visible ~allow_empty:true select
  | Ast.In_subquery (expression, select) | Ast.Not_in_subquery (expression, select) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible expression in
    validate_subquery ~outer_visible:visible ~allow_empty:false select
  | Ast.And conditions | Ast.Or conditions ->
    validate_conditions ~validate_subquery ~visible conditions
  | Ast.Not condition -> validate_condition ~validate_subquery ~visible condition

and validate_conditions ~validate_subquery ~visible = function
  | [] -> Ok ()
  | condition :: rest ->
    let open Result.Let_syntax in
    let%bind () = validate_condition ~validate_subquery ~visible condition in
    validate_conditions ~validate_subquery ~visible rest

and validate_expressions ~validate_subquery ~visible = function
  | [] -> Ok ()
  | expression :: rest ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible expression in
    validate_expressions ~validate_subquery ~visible rest
;;

let validate_joins ~validate_subquery ~outer_visible source_id (joins : Ast.join list) =
  let rec loop visible = function
    | [] -> Ok visible
    | (join : Ast.join) :: rest ->
      let visible = visible @ [ join.Ast.source.source_id ] in
      let open Result.Let_syntax in
      let%bind () = validate_condition ~validate_subquery ~visible join.on in
      loop visible rest
  in
  loop (outer_visible @ [ source_id ]) joins
;;

let same_column left right =
  match left, right with
  | ( Ast.Column { source_id = left_source; name = left_name; _ }
    , Ast.Column { source_id = right_source; name = right_name; _ } ) ->
    Int.(left_source = right_source) && Identifier.equal left_name right_name
  | _ -> false
;;

let same_arithmetic left right =
  match left, right with
  | Ast.Add, Ast.Add
  | Ast.Subtract, Ast.Subtract
  | Ast.Multiply, Ast.Multiply
  | Ast.Divide, Ast.Divide -> true
  | _ -> false
;;

let same_string_function left right =
  match left, right with
  | Ast.Lower, Ast.Lower | Ast.Upper, Ast.Upper | Ast.Length, Ast.Length -> true
  | _ -> false
;;

let rec same_group_expression left right =
  if same_column left right then
    true
  else (
    match
      left, right
    with
    | ( Ast.Arithmetic (left_operator, left_a, left_b)
      , Ast.Arithmetic (right_operator, right_a, right_b) ) ->
      same_arithmetic left_operator right_operator
      && same_group_expression left_a right_a
      && same_group_expression left_b right_b
    | ( Ast.String_function (left_function, left)
      , Ast.String_function (right_function, right) ) ->
      same_string_function left_function right_function
      && same_group_expression left right
    | Ast.Concat (left_a, left_b), Ast.Concat (right_a, right_b) ->
      same_group_expression left_a right_a && same_group_expression left_b right_b
    | _ -> false)
;;

type aggregate_analysis =
  { has_aggregate : bool
  ; nested_aggregate : bool
  ; grouped : bool
  }

let plain ~grouped = { has_aggregate = false; nested_aggregate = false; grouped }

let combine left right =
  { has_aggregate = left.has_aggregate || right.has_aggregate
  ; nested_aggregate = left.nested_aggregate || right.nested_aggregate
  ; grouped = left.grouped && right.grouped
  }
;;

let combine_all values = List.fold values ~init:(plain ~grouped:true) ~f:combine

let rec analyze_expression ~groups ~inside_aggregate expression =
  if List.exists groups ~f:(same_group_expression expression) then
    plain ~grouped:true
  else (
    match
      expression
    with
    | Ast.Column _ -> plain ~grouped:false
    | Ast.Param _ | Ast.Current_timestamp | Ast.Scalar_subquery _ -> plain ~grouped:true
    | Ast.Arithmetic (_, left, right) | Ast.Concat (left, right) ->
      combine
        (analyze_expression ~groups ~inside_aggregate left)
        (analyze_expression ~groups ~inside_aggregate right)
    | Ast.String_function (_, expression) ->
      analyze_expression ~groups ~inside_aggregate expression
    | Ast.Case (branches, else_) ->
      let branches =
        List.concat_map branches ~f:(fun (condition, expression) ->
          [ analyze_condition ~groups ~inside_aggregate condition
          ; analyze_expression ~groups ~inside_aggregate expression
          ])
      in
      combine_all (analyze_expression ~groups ~inside_aggregate else_ :: branches)
    | Ast.Aggregate Ast.Count_all ->
      { has_aggregate = true; nested_aggregate = inside_aggregate; grouped = true }
    | Ast.Aggregate (Ast.Count expression | Ast.Count_distinct expression) ->
      let nested = analyze_expression ~groups ~inside_aggregate:true expression in
      { has_aggregate = true
      ; nested_aggregate = inside_aggregate || nested.nested_aggregate
      ; grouped = true
      })

and analyze_condition ~groups ~inside_aggregate = function
  | Ast.True | Ast.False | Ast.Exists _ | Ast.Not_exists _ -> plain ~grouped:true
  | Ast.Compare (_, left, right) ->
    combine
      (analyze_expression ~groups ~inside_aggregate left)
      (analyze_expression ~groups ~inside_aggregate right)
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    analyze_expression ~groups ~inside_aggregate expression
  | Ast.In (expression, values) | Ast.Not_in (expression, values) ->
    combine_all
      (analyze_expression ~groups ~inside_aggregate expression
       :: List.map values ~f:(analyze_expression ~groups ~inside_aggregate))
  | Ast.Between (expression, lower, upper) ->
    combine_all
      (List.map
         [ expression; lower; upper ]
         ~f:(analyze_expression ~groups ~inside_aggregate))
  | Ast.In_subquery (expression, _) | Ast.Not_in_subquery (expression, _) ->
    analyze_expression ~groups ~inside_aggregate expression
  | Ast.And conditions | Ast.Or conditions ->
    List.map conditions ~f:(analyze_condition ~groups ~inside_aggregate) |> combine_all
  | Ast.Not condition -> analyze_condition ~groups ~inside_aggregate condition
;;

let ensure_no_aggregate clause condition =
  if (analyze_condition ~groups:[] ~inside_aggregate:false condition).has_aggregate then
    Error (Compile_error.Aggregate_not_allowed clause)
  else
    Ok ()
;;

let rec validate_select ~outer_visible ~allow_empty (select : Ast.select) =
  if (not allow_empty) && List.is_empty select.Ast.projection then
    Error Compile_error.Empty_projection
  else if Option.exists select.limit ~f:(fun value -> value < 0) then
    Error (Compile_error.Negative_limit (Option.value_exn select.limit))
  else if Option.exists select.offset ~f:(fun value -> value < 0) then
    Error (Compile_error.Negative_offset (Option.value_exn select.offset))
  else
    let open Result.Let_syntax in
    let%bind visible =
      validate_joins
        ~validate_subquery:validate_select
        ~outer_visible
        select.source.source_id
        select.joins
    in
    let%bind () =
      List.fold select.joins ~init:(Ok ()) ~f:(fun result join ->
        let%bind () = result in
        ensure_no_aggregate "JOIN ON" join.Ast.on)
    in
    let%bind () =
      validate_expressions ~validate_subquery:validate_select ~visible select.projection
    in
    let%bind () =
      match select.where_ with
      | None -> Ok ()
      | Some condition ->
        let%bind () =
          validate_condition ~validate_subquery:validate_select ~visible condition
        in
        ensure_no_aggregate "WHERE" condition
    in
    let%bind () =
      validate_expressions ~validate_subquery:validate_select ~visible select.group_by
    in
    let%bind () =
      if
        List.exists select.group_by ~f:(fun expression ->
          (analyze_expression ~groups:[] ~inside_aggregate:false expression).has_aggregate)
      then
        Error (Compile_error.Aggregate_not_allowed "GROUP BY")
      else
        Ok ()
    in
    let%bind () =
      match select.having with
      | None -> Ok ()
      | Some condition ->
        validate_condition ~validate_subquery:validate_select ~visible condition
    in
    let order_by = List.map select.order_by ~f:(fun order -> order.Ast.expr) in
    let%bind () =
      validate_expressions ~validate_subquery:validate_select ~visible order_by
    in
    let expressions = select.projection @ order_by in
    let analyses =
      List.map expressions ~f:(fun expression ->
        analyze_expression ~groups:select.group_by ~inside_aggregate:false expression)
      @ Option.value_map select.having ~default:[] ~f:(fun condition ->
        [ analyze_condition ~groups:select.group_by ~inside_aggregate:false condition ])
    in
    if List.exists analyses ~f:(fun analysis -> analysis.nested_aggregate) then
      Error Compile_error.Nested_aggregate
    else (
      let aggregate_query =
        (not (List.is_empty select.group_by))
        || Option.is_some select.having
        || List.exists analyses ~f:(fun analysis -> analysis.has_aggregate)
      in
      if aggregate_query && List.exists analyses ~f:(fun analysis -> not analysis.grouped)
      then
        Error Compile_error.Ungrouped_expression
      else
        Ok ())
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
    if Int.(assignment.Ast.source_id <> source_id) then
      Error
        (Compile_error.Invalid_assignment_source
           { expected = source_id; actual = assignment.source_id })
    else
      let open Result.Let_syntax in
      let%bind () =
        match assignment.value with
        | Ast.Default -> Ok ()
        | Ast.Expression expression ->
          validate_expr ~validate_subquery:validate_select ~visible expression
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
            validate_assignments ~source_id ~visible:[] assignments)
    in
    let open Result.Let_syntax in
    let%bind () = validate_row 1 first in
    List.foldi rest ~init:(Ok ()) ~f:(fun index result assignments ->
      let%bind () = result in
      validate_row (index + 2) assignments)
;;

let duplicate_conflict_column targets =
  let rec loop seen = function
    | [] -> None
    | target :: rest ->
      if List.mem seen target.Ast.target_column ~equal:Identifier.equal then
        Some target.target_column
      else
        loop (target.target_column :: seen) rest
  in
  loop [] targets
;;

let validate_conflict_target ~source_id target =
  if List.is_empty target then
    Error Compile_error.Empty_conflict_target
  else (
    match
      List.find target ~f:(fun target -> Int.(target.Ast.target_source_id <> source_id))
    with
    | Some target ->
      Error
        (Compile_error.Invalid_conflict_target_source
           { expected = source_id; actual = target.target_source_id })
    | None ->
      (match duplicate_conflict_column target with
       | None -> Ok ()
       | Some column -> Error (Compile_error.Duplicate_conflict_target column)))
;;

let validate_conflict ~source_id = function
  | Ast.Do_nothing None -> Ok ()
  | Ast.Do_nothing (Some target) -> validate_conflict_target ~source_id target
  | Ast.Do_update { target; excluded_source_id; assignments; where_ } ->
    let open Result.Let_syntax in
    let%bind () = validate_conflict_target ~source_id target in
    (match duplicate_assignment assignments with
     | Some column -> Error (Compile_error.Duplicate_assignment column)
     | None ->
       if List.is_empty assignments then
         Error Compile_error.Empty_conflict_update
       else (
         let visible = [ source_id; excluded_source_id ] in
         let%bind () = validate_assignments ~source_id ~visible assignments in
         let%bind () =
           List.fold assignments ~init:(Ok ()) ~f:(fun result assignment ->
             let%bind () = result in
             match assignment.Ast.value with
             | Ast.Default -> Ok ()
             | Ast.Expression expression ->
               if
                 (analyze_expression ~groups:[] ~inside_aggregate:false expression)
                   .has_aggregate
               then
                 Error (Compile_error.Aggregate_not_allowed "ON CONFLICT DO UPDATE SET")
               else
                 Ok ())
         in
         match where_ with
         | None -> Ok ()
         | Some condition ->
           let%bind () =
             validate_condition ~validate_subquery:validate_select ~visible condition
           in
           ensure_no_aggregate "ON CONFLICT DO UPDATE WHERE" condition))
;;

let validate_command (command : Ast.command) =
  match command.Ast.kind with
  | Ast.Insert ->
    let open Result.Let_syntax in
    let source_id = command.source.source_id in
    let%bind () = validate_insert_rows ~source_id command.rows in
    (match command.conflict with
     | None -> Ok ()
     | Some conflict -> validate_conflict ~source_id conflict)
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
         | Some condition ->
           validate_condition ~validate_subquery:validate_select ~visible condition))
  | Ast.Delete ->
    (match command.where_ with
     | None -> Ok ()
     | Some condition ->
       let visible = [ command.source.source_id ] in
       let open Result.Let_syntax in
       validate_condition ~validate_subquery:validate_select ~visible condition)
;;

let result_query = function
  | Ast.Select select -> validate_select ~outer_visible:[] ~allow_empty:false select
  | Ast.Returning returning ->
    if List.is_empty returning.projection then
      Error Compile_error.Empty_projection
    else
      let open Result.Let_syntax in
      let%bind () = validate_command returning.command in
      let visible = [ returning.command.source.source_id ] in
      validate_expressions
        ~validate_subquery:validate_select
        ~visible
        returning.projection
;;

let command = validate_command
