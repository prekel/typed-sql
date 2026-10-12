open! Base

let validate_db_type (Db_type.Pack db_type) =
  match Db_type.invalid_type db_type with
  | None -> Ok ()
  | Some message -> Error (Compile_error.Invalid_db_type message)
;;

let packed_sql_type (Db_type.Pack typ) = Db_type.sql_type_name typ

let numeric_sql_type = function
  | Ast.Int -> "integer"
  | Ast.Int64 -> "bigint"
  | Ast.Float -> "double precision"
  | Ast.Numeric -> "numeric"
;;

let rec expression_sql_type = function
  | Ast.Column { db_type; _ } | Ast.Param (Ast.Slot { db_type; _ }) ->
    Some (packed_sql_type db_type)
  | Ast.Param (Ast.Value (Db_type.Value (typ, _))) -> Some (Db_type.sql_type_name typ)
  | Ast.Arithmetic (_, left, _) -> expression_sql_type left
  | Ast.Cast (_, target, _) -> Some (numeric_sql_type target)
  | Ast.String_function ((Ast.Length | Ast.Sqlite_length), _) -> Some "integer"
  | Ast.String_function ((Ast.Lower | Ast.Upper), _) | Ast.Concat _ -> Some "text"
  | Ast.Coalesce (_, default) | Ast.Case (_, default) -> expression_sql_type default
  | Ast.Current_timestamp -> Some "timestamp with time zone"
  | Ast.Exists_expr _ -> Some "boolean"
  | Ast.Multiset_subquery _ | Ast.Aggregate (Ast.Multiset_agg _) -> Some "jsonb"
  | Ast.Scalar_subquery select -> scalar_sql_type select
  | Ast.Aggregate (Ast.Count_all | Ast.Count _ | Ast.Count_distinct _ | Ast.Sum_int _) ->
    Some "bigint"
  | Ast.Aggregate (Ast.Sum_float _ | Ast.Avg_float _) -> Some "double precision"
  | Ast.Aggregate (Ast.Sum_int64 _ | Ast.Sum_numeric _ | Ast.Avg_numeric _) ->
    Some "numeric"
  | Ast.Aggregate (Ast.Min value | Ast.Max value) -> expression_sql_type value
  | Ast.Aggregate (Ast.String_agg _) -> Some "text"

and scalar_sql_type (select : Ast.select) =
  match select.projection with
  | [ expression ] -> expression_sql_type expression
  | _ -> None
;;

let check_sql_types ~context expected actual =
  match expected, actual with
  | Some expected, Some actual when String.equal expected actual -> Ok ()
  | Some expected, Some actual ->
    Error (Compile_error.Mismatched_sql_type { context; expected; actual })
  | _ -> Error Compile_error.Empty_projection
;;

let check_expression_types ~context left right =
  check_sql_types ~context (expression_sql_type left) (expression_sql_type right)
;;

let rec validate_expr ~validate_subquery ~visible = function
  | Ast.Param (Ast.Value (Db_type.Value (db_type, _))) ->
    validate_db_type (Db_type.Pack db_type)
  | Ast.Param (Ast.Slot { db_type; _ }) -> validate_db_type db_type
  | Ast.Column { source_id; db_type; _ } ->
    let open Result.Let_syntax in
    let%bind () = validate_db_type db_type in
    if List.mem visible source_id ~equal:Int.equal then
      Ok ()
    else
      Error (Compile_error.Foreign_source { visible; actual = source_id })
  | Ast.Arithmetic (_, left, right) | Ast.Concat (left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible left in
    validate_expr ~validate_subquery ~visible right
  | Ast.Coalesce (left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible left in
    let%bind () = validate_expr ~validate_subquery ~visible right in
    check_expression_types ~context:"COALESCE" right left
  | Ast.Cast (_, _, expression) | Ast.String_function (_, expression) ->
    validate_expr ~validate_subquery ~visible expression
  | Ast.Case (branches, else_) ->
    let open Result.Let_syntax in
    let%bind () =
      List.fold branches ~init:(Ok ()) ~f:(fun result (condition, expression) ->
        let%bind () = result in
        let%bind () = validate_condition ~validate_subquery ~visible condition in
        let%bind () = validate_expr ~validate_subquery ~visible expression in
        check_expression_types ~context:"CASE" else_ expression)
    in
    validate_expr ~validate_subquery ~visible else_
  | Ast.Aggregate Ast.Count_all -> Ok ()
  | Ast.Aggregate
      ( Ast.Count expression
      | Ast.Count_distinct expression
      | Ast.Sum_int expression
      | Ast.Sum_float expression
      | Ast.Sum_int64 expression
      | Ast.Sum_numeric expression
      | Ast.Avg_float expression
      | Ast.Avg_numeric expression
      | Ast.Min expression
      | Ast.Max expression ) -> validate_expr ~validate_subquery ~visible expression
  | Ast.Aggregate (Ast.String_agg { value; delimiter; order_by }) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible value in
    let%bind () = validate_expr ~validate_subquery ~visible delimiter in
    List.map order_by ~f:(fun order -> order.Ast.expr)
    |> validate_expressions ~validate_subquery ~visible
  | Ast.Aggregate (Ast.Multiset_agg multiset) ->
    let open Result.Let_syntax in
    let%bind () = validate_expressions ~validate_subquery ~visible multiset.fields in
    let%bind () =
      match multiset.filter with
      | None -> Ok ()
      | Some filter -> validate_condition ~validate_subquery ~visible filter
    in
    let%bind () =
      List.map multiset.order_by ~f:(fun order -> order.Ast.expr)
      |> validate_expressions ~validate_subquery ~visible
    in
    validate_multiset_types multiset.field_types
  | Ast.Scalar_subquery select ->
    let open Result.Let_syntax in
    let%bind () =
      validate_subquery ~outer_visible:visible ~allow_empty:false (Ast.Simple select)
    in
    if Aggregate_scope.at_most_one select then
      Ok ()
    else
      Error Compile_error.Scalar_subquery_may_return_many_rows
  | Ast.Multiset_subquery multiset ->
    let open Result.Let_syntax in
    let%bind () =
      validate_subquery ~outer_visible:visible ~allow_empty:false multiset.query
    in
    validate_multiset_types multiset.field_types
  | Ast.Exists_expr select ->
    validate_subquery ~outer_visible:visible ~allow_empty:true (Ast.Simple select)
  | Ast.Current_timestamp -> Ok ()

and validate_condition ~validate_subquery ~visible = function
  | Ast.True | Ast.False -> Ok ()
  | Ast.Compare (_, left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible left in
    let%bind () = validate_expr ~validate_subquery ~visible right in
    check_expression_types ~context:"comparison" left right
  | Ast.Equals_any (left, right) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible left in
    let%bind () = validate_expr ~validate_subquery ~visible right in
    let element_type =
      Option.bind (expression_sql_type right) ~f:(String.chop_suffix ~suffix:"[]")
    in
    check_sql_types ~context:"ANY" (expression_sql_type left) element_type
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    validate_expr ~validate_subquery ~visible expression
  | Ast.In (expression, values) | Ast.Not_in (expression, values) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible expression in
    let%bind () = validate_expressions ~validate_subquery ~visible values in
    Result.all_unit (List.map values ~f:(check_expression_types ~context:"IN" expression))
  | Ast.Between (expression, lower, upper) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible expression in
    let%bind () = validate_expr ~validate_subquery ~visible lower in
    let%bind () = validate_expr ~validate_subquery ~visible upper in
    let%bind () = check_expression_types ~context:"BETWEEN" expression lower in
    check_expression_types ~context:"BETWEEN" expression upper
  | Ast.Exists select | Ast.Not_exists select ->
    validate_subquery ~outer_visible:visible ~allow_empty:true (Ast.Simple select)
  | Ast.In_subquery (expression, select) | Ast.Not_in_subquery (expression, select) ->
    let open Result.Let_syntax in
    let%bind () = validate_expr ~validate_subquery ~visible expression in
    let%bind () =
      validate_subquery ~outer_visible:visible ~allow_empty:false (Ast.Simple select)
    in
    check_sql_types
      ~context:"IN subquery"
      (expression_sql_type expression)
      (scalar_sql_type select)
  | Ast.And conditions | Ast.Or conditions ->
    validate_conditions ~validate_subquery ~visible conditions
  | Ast.Not condition -> validate_condition ~validate_subquery ~visible condition

and validate_multiset_types types =
  if List.is_empty types then
    Error Compile_error.Empty_projection
  else (
    match
      List.find_mapi types ~f:(fun index (Db_type.Pack db_type) ->
        Db_type.unsupported_multiset_type ~path:[ index + 1 ] db_type)
    with
    | None -> Ok ()
    | Some (path, type_name) ->
      Error (Compile_error.Unsupported_multiset_field_type { path; type_name }))

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
      let%bind () =
        match join.operation with
        | Ast.Cross -> Ok ()
        | Ast.Predicate (_, on) -> validate_condition ~validate_subquery ~visible on
      in
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

let same_numeric_type left right =
  match left, right with
  | Ast.Int, Ast.Int
  | Ast.Int64, Ast.Int64
  | Ast.Float, Ast.Float
  | Ast.Numeric, Ast.Numeric -> true
  | _ -> false
;;

let same_comparison left right =
  match left, right with
  | Ast.Eq, Ast.Eq
  | Ast.Neq, Ast.Neq
  | Ast.Lt, Ast.Lt
  | Ast.Lte, Ast.Lte
  | Ast.Gt, Ast.Gt
  | Ast.Gte, Ast.Gte
  | Ast.Like, Ast.Like
  | Ast.Is_distinct_from, Ast.Is_distinct_from
  | Ast.Sqlite_is_not, Ast.Sqlite_is_not -> true
  | _ -> false
;;

let rec same_group_expression left right =
  if same_column left right then
    true
  else (
    match
      left, right
    with
    | Ast.Param (Ast.Slot left), Ast.Param (Ast.Slot right) -> Int.equal left.id right.id
    | Ast.Param left, Ast.Param right -> phys_equal left right
    | Ast.Current_timestamp, Ast.Current_timestamp -> true
    | Ast.Case (left, left_else), Ast.Case (right, right_else) ->
      List.equal
        (fun (a, x) (b, y) -> same_group_condition a b && same_group_expression x y)
        left
        right
      && same_group_expression left_else right_else
    | ( Ast.Arithmetic (left_operator, left_a, left_b)
      , Ast.Arithmetic (right_operator, right_a, right_b) ) ->
      same_arithmetic left_operator right_operator
      && same_group_expression left_a right_a
      && same_group_expression left_b right_b
    | ( Ast.String_function (left_function, left)
      , Ast.String_function (right_function, right) ) ->
      same_string_function left_function right_function
      && same_group_expression left right
    | Ast.Cast (sa, ta, a), Ast.Cast (sb, tb, b) ->
      same_numeric_type sa sb && same_numeric_type ta tb && same_group_expression a b
    | Ast.Concat (left_a, left_b), Ast.Concat (right_a, right_b) ->
      same_group_expression left_a right_a && same_group_expression left_b right_b
    | Ast.Coalesce (left_a, left_b), Ast.Coalesce (right_a, right_b) ->
      same_group_expression left_a right_a && same_group_expression left_b right_b
    | _ -> false)

and same_group_condition left right =
  match left, right with
  | Ast.True, Ast.True | Ast.False, Ast.False -> true
  | Ast.Compare (a, x, y), Ast.Compare (b, u, v) ->
    same_comparison a b && same_group_expression x u && same_group_expression y v
  | Ast.Equals_any (x, y), Ast.Equals_any (u, v) ->
    same_group_expression x u && same_group_expression y v
  | Ast.Is_null x, Ast.Is_null y | Ast.Is_not_null x, Ast.Is_not_null y ->
    same_group_expression x y
  | Ast.In (x, xs), Ast.In (y, ys) | Ast.Not_in (x, xs), Ast.Not_in (y, ys) ->
    same_group_expression x y && List.equal same_group_expression xs ys
  | Ast.Between (x, lo, hi), Ast.Between (y, lo', hi') ->
    same_group_expression x y
    && same_group_expression lo lo'
    && same_group_expression hi hi'
  | Ast.And xs, Ast.And ys | Ast.Or xs, Ast.Or ys -> List.equal same_group_condition xs ys
  | Ast.Not x, Ast.Not y -> same_group_condition x y
  | _ -> false
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

let rec analyze_expression
          ?(sources = [])
          ?(correlations = false)
          ~groups
          ~inside_aggregate
          expression
  =
  if List.exists groups ~f:(same_group_expression expression) then
    plain ~grouped:true
  else (
    match
      expression
    with
    | Ast.Column { source_id; _ } ->
      plain
        ~grouped:
          ((correlations || not (List.is_empty sources))
           && not (List.mem sources source_id ~equal:Int.equal))
    | Ast.Param _ | Ast.Current_timestamp -> plain ~grouped:true
    | Ast.Scalar_subquery select | Ast.Exists_expr select ->
      analyze_correlations ~groups ~sources ~inside_aggregate (Ast.Simple select)
    | Ast.Multiset_subquery multiset ->
      analyze_correlations ~groups ~sources ~inside_aggregate multiset.query
    | Ast.Arithmetic (_, left, right)
    | Ast.Concat (left, right)
    | Ast.Coalesce (left, right) ->
      combine
        (analyze_expression ~groups ~sources ~correlations ~inside_aggregate left)
        (analyze_expression ~groups ~sources ~correlations ~inside_aggregate right)
    | Ast.Cast (_, _, expression) | Ast.String_function (_, expression) ->
      analyze_expression ~groups ~sources ~correlations ~inside_aggregate expression
    | Ast.Case (branches, else_) ->
      let branches =
        List.concat_map branches ~f:(fun (condition, expression) ->
          [ analyze_condition ~groups ~sources ~correlations ~inside_aggregate condition
          ; analyze_expression ~groups ~sources ~correlations ~inside_aggregate expression
          ])
      in
      combine_all
        (analyze_expression ~groups ~sources ~correlations ~inside_aggregate else_
         :: branches)
    | Ast.Aggregate aggregate ->
      analyze_aggregate ~groups ~sources ~correlations ~inside_aggregate aggregate)

and analyze_aggregate ~groups ~sources ~correlations ~inside_aggregate aggregate =
  let referenced = Aggregate_scope.aggregate_sources aggregate in
  let belongs_to_scope =
    (not correlations)
    || ((not (List.is_empty referenced))
        && List.for_all referenced ~f:(fun source ->
          List.mem sources source ~equal:Int.equal))
  in
  let expression =
    analyze_expression
      ~groups
      ~sources
      ~correlations
      ~inside_aggregate:(inside_aggregate || belongs_to_scope)
  in
  let condition =
    analyze_condition
      ~groups
      ~sources
      ~correlations
      ~inside_aggregate:(inside_aggregate || belongs_to_scope)
  in
  let nested =
    match aggregate with
    | Ast.Count_all -> plain ~grouped:true
    | Ast.Count value
    | Ast.Count_distinct value
    | Ast.Sum_int value
    | Ast.Sum_float value
    | Ast.Sum_int64 value
    | Ast.Sum_numeric value
    | Ast.Avg_float value
    | Ast.Avg_numeric value
    | Ast.Min value
    | Ast.Max value -> expression value
    | Ast.String_agg { value; delimiter; order_by } ->
      combine_all
        (expression value
         :: expression delimiter
         :: List.map order_by ~f:(fun order -> expression order.Ast.expr))
    | Ast.Multiset_agg multiset ->
      combine_all
        (List.map multiset.fields ~f:expression
         @ List.map multiset.order_by ~f:(fun order -> expression order.Ast.expr)
         @ Option.value_map multiset.filter ~default:[] ~f:(fun filter ->
           [ condition filter ]))
  in
  if belongs_to_scope then
    { has_aggregate = true
    ; nested_aggregate =
        inside_aggregate || nested.has_aggregate || nested.nested_aggregate
    ; grouped = true
    }
  else
    nested

and analyze_condition ?(sources = []) ?(correlations = false) ~groups ~inside_aggregate
  = function
  | Ast.True | Ast.False -> plain ~grouped:true
  | Ast.Exists select | Ast.Not_exists select ->
    analyze_correlations ~groups ~sources ~inside_aggregate (Ast.Simple select)
  | Ast.Compare (_, left, right) | Ast.Equals_any (left, right) ->
    combine
      (analyze_expression ~groups ~sources ~correlations ~inside_aggregate left)
      (analyze_expression ~groups ~sources ~correlations ~inside_aggregate right)
  | Ast.Is_null expression | Ast.Is_not_null expression ->
    analyze_expression ~groups ~sources ~correlations ~inside_aggregate expression
  | Ast.In (expression, values) | Ast.Not_in (expression, values) ->
    combine_all
      (analyze_expression ~groups ~sources ~correlations ~inside_aggregate expression
       :: List.map
            values
            ~f:(analyze_expression ~groups ~sources ~correlations ~inside_aggregate))
  | Ast.Between (expression, lower, upper) ->
    combine_all
      (List.map
         [ expression; lower; upper ]
         ~f:(analyze_expression ~groups ~sources ~correlations ~inside_aggregate))
  | Ast.In_subquery (expression, select) | Ast.Not_in_subquery (expression, select) ->
    combine
      (analyze_expression ~groups ~sources ~correlations ~inside_aggregate expression)
      (analyze_correlations ~groups ~sources ~inside_aggregate (Ast.Simple select))
  | Ast.And conditions | Ast.Or conditions ->
    List.map
      conditions
      ~f:(analyze_condition ~groups ~sources ~correlations ~inside_aggregate)
    |> combine_all
  | Ast.Not condition ->
    analyze_condition ~groups ~sources ~correlations ~inside_aggregate condition

and analyze_correlations ~groups ~sources ~inside_aggregate query =
  let expression =
    analyze_expression ~groups ~sources ~correlations:true ~inside_aggregate
  in
  let condition =
    analyze_condition ~groups ~sources ~correlations:true ~inside_aggregate
  in
  let optional f value = Option.value_map value ~default:(plain ~grouped:true) ~f in
  let source (source : Ast.source) =
    match source.kind with
    | Ast.Derived relation ->
      analyze_correlations ~groups ~sources ~inside_aggregate relation.query
    | Ast.Values values ->
      combine_all
        (List.concat_map values.rows ~f:(fun row ->
           List.map row.Ast.expressions ~f:expression))
    | Ast.Table _ | Ast.Cte _ -> plain ~grouped:true
  in
  match query with
  | Ast.Simple select ->
    combine_all
      (List.map
         (select.projection
          @ select.group_by
          @ List.map select.order_by ~f:(fun order -> order.Ast.expr))
         ~f:expression
       @ [ optional condition select.where_
         ; optional condition select.having
         ; source select.source
         ]
       @ List.concat_map select.joins ~f:(fun join ->
         [ source join.Ast.source
         ; (match join.operation with
            | Ast.Cross -> plain ~grouped:true
            | Ast.Predicate (_, on) -> condition on)
         ]))
  | Ast.Source_free free -> expression free.expression
  | Ast.Compound compound ->
    combine
      (analyze_correlations ~groups ~sources ~inside_aggregate compound.left)
      (analyze_correlations ~groups ~sources ~inside_aggregate compound.right)
;;

let ensure_no_aggregate ?(sources = []) clause condition =
  if
    (analyze_condition ~sources ~groups:[] ~inside_aggregate:false condition)
      .has_aggregate
  then
    Error (Compile_error.Aggregate_not_allowed clause)
  else
    Ok ()
;;

let ensure_no_assignment_aggregate ~visible clause assignments =
  if
    List.exists assignments ~f:(fun assignment ->
      match assignment.Ast.value with
      | Ast.Default -> false
      | Ast.Expression expression ->
        (analyze_expression
           ~sources:visible
           ~groups:[]
           ~inside_aggregate:false
           expression)
          .has_aggregate)
  then
    Error (Compile_error.Aggregate_not_allowed clause)
  else
    Ok ()
;;

let validate_values ~validate_subquery (values : Ast.values) =
  let open Result.Let_syntax in
  if List.is_empty values.columns then
    Error Compile_error.Empty_values_columns
  else if List.is_empty values.rows then
    Error Compile_error.Empty_values_rows
  else (
    let%bind columns =
      List.mapi values.columns ~f:(fun index -> function
        | Ast.Column { source_id; name; db_type }
          when Int.equal source_id values.descriptor_source_id -> Ok (name, db_type)
        | _ -> Error (Compile_error.Invalid_relation_column (index + 1)))
      |> Result.all
    in
    let names = List.map columns ~f:fst in
    let rec find_duplicate seen = function
      | [] -> None
      | name :: rest ->
        if List.mem seen name ~equal:Identifier.equal then
          Some name
        else
          find_duplicate (name :: seen) rest
    in
    let%bind () =
      match find_duplicate [] names with
      | None -> Ok ()
      | Some name -> Error (Compile_error.Duplicate_relation_column name)
    in
    let fingerprints types =
      List.map types ~f:(fun (Db_type.Pack db_type) -> Db_type.fingerprint db_type)
    in
    let column_types = List.map columns ~f:snd in
    let expected_row_types = fingerprints column_types in
    List.foldi values.rows ~init:(Ok ()) ~f:(fun index result row ->
      let%bind () = result in
      let row_number = index + 1 in
      let actual_width = List.length row.expressions in
      let expected_width = List.length values.columns in
      if not (Int.equal actual_width expected_width) then
        Error
          (Compile_error.Mismatched_values_row_arity
             { row = row_number; expected = expected_width; actual = actual_width })
      else (
        let actual_types = fingerprints row.types in
        if not (List.equal String.equal expected_row_types actual_types) then
          Error
            (Compile_error.Mismatched_values_row_types
               { row = row_number; expected = expected_row_types; actual = actual_types })
        else (
          let%bind () =
            validate_expressions ~validate_subquery ~visible:[] row.expressions
          in
          List.fold row.expressions ~init:(Ok ()) ~f:(fun result expression ->
            let%bind () = result in
            if
              (analyze_expression ~groups:[] ~inside_aggregate:false expression)
                .has_aggregate
            then
              Error (Compile_error.Aggregate_not_allowed "VALUES")
            else
              Ok ())))))
;;

let validate_locking (select : Ast.select) ~aggregate_query =
  let open Result.Let_syntax in
  match select.locking with
  | None -> Ok ()
  | Some locking ->
    if select.distinct then
      Error (Compile_error.Invalid_for_update "cannot be used with DISTINCT")
    else if aggregate_query then
      Error (Compile_error.Invalid_for_update "cannot be used with aggregation")
    else if
      locking.skip_locked
      && Option.exists select.limit ~f:(function
        | Ast.Fetch_with_ties _ -> true
        | Ast.Limit _ -> false)
    then
      Error
        (Compile_error.Invalid_for_update
           "SKIP LOCKED cannot be used with FETCH WITH TIES")
    else (
      let sources =
        (select.source, false)
        :: List.map select.joins ~f:(fun join ->
          ( join.Ast.source
          , match join.operation with
            | Ast.Cross | Ast.Predicate (Ast.Inner, _) -> false
            | Ast.Predicate (Ast.Left, _) -> true ))
      in
      let%bind targets =
        match locking.of_sources with
        | None -> Ok (List.map sources ~f:(fun (source, _) -> source.Ast.source_id))
        | Some [] ->
          Error (Compile_error.Invalid_for_update "OF requires at least one table")
        | Some targets -> Ok targets
      in
      let%map _ =
        List.fold targets ~init:(Ok []) ~f:(fun checked target ->
          let%bind checked = checked in
          if List.mem checked target ~equal:Int.equal then
            Error (Compile_error.Invalid_for_update "OF repeats a table")
          else (
            match
              List.find sources ~f:(fun (source, _) ->
                Int.equal source.Ast.source_id target)
            with
            | None ->
              Error (Compile_error.Invalid_for_update "OF references a foreign source")
            | Some (_, true) ->
              Error
                (Compile_error.Invalid_for_update
                   "cannot lock the nullable side of an outer join")
            | Some ({ kind = Ast.Table _; _ }, false) -> Ok (target :: checked)
            | Some ({ kind = Ast.Derived _ | Ast.Values _ | Ast.Cte _; _ }, false) ->
              Error (Compile_error.Invalid_for_update "requires a base table source")))
      in
      ())
;;

let validate_select_with
      ~validate_subquery
      ~outer_visible
      ~allow_empty
      (select : Ast.select)
  =
  let negative_limit =
    Option.bind select.limit ~f:(function
      | Ast.Limit (Ast.Literal value) when value < 0 ->
        Some (Compile_error.Negative_limit value)
      | Ast.Fetch_with_ties (Ast.Literal value) when value < 0 ->
        Some (Compile_error.Negative_fetch_count value)
      | Ast.Limit _ | Ast.Fetch_with_ties _ -> None)
  in
  let negative_offset =
    Option.bind select.offset ~f:(function
      | Ast.Literal value when value < 0 -> Some (Compile_error.Negative_offset value)
      | Ast.Literal _ | Ast.Parameter _ -> None)
  in
  if (not allow_empty) && List.is_empty select.Ast.projection then
    Error Compile_error.Empty_projection
  else if Option.is_some negative_limit then
    Error (Option.value_exn negative_limit)
  else if
    Option.exists select.limit ~f:(function
      | Ast.Fetch_with_ties _ -> List.is_empty select.order_by
      | Ast.Limit _ -> false)
  then
    Error Compile_error.Fetch_with_ties_requires_order_by
  else if Option.is_some negative_offset then
    Error (Option.value_exn negative_offset)
  else
    let open Result.Let_syntax in
    let sources =
      select.source.source_id
      :: List.map select.joins ~f:(fun join -> join.Ast.source.source_id)
    in
    let validate_values_source (source : Ast.source) =
      match source.Ast.kind with
      | Ast.Values values -> validate_values ~validate_subquery values
      | Ast.Table _ | Ast.Derived _ | Ast.Cte _ -> Ok ()
    in
    let%bind () = validate_values_source select.source in
    let%bind () =
      List.fold select.joins ~init:(Ok ()) ~f:(fun result join ->
        let%bind () = result in
        validate_values_source join.Ast.source)
    in
    let%bind visible =
      validate_joins
        ~validate_subquery
        ~outer_visible
        select.source.source_id
        select.joins
    in
    let%bind () =
      List.fold select.joins ~init:(Ok ()) ~f:(fun result join ->
        let%bind () = result in
        match join.Ast.operation with
        | Ast.Cross -> Ok ()
        | Ast.Predicate (_, on) -> ensure_no_aggregate ~sources "JOIN ON" on)
    in
    let%bind () = validate_expressions ~validate_subquery ~visible select.projection in
    let%bind () =
      match select.where_ with
      | None -> Ok ()
      | Some condition ->
        let%bind () = validate_condition ~validate_subquery ~visible condition in
        ensure_no_aggregate ~sources "WHERE" condition
    in
    let%bind () = validate_expressions ~validate_subquery ~visible select.group_by in
    let%bind () =
      if
        List.exists select.group_by ~f:(fun expression ->
          (analyze_expression ~sources ~groups:[] ~inside_aggregate:false expression)
            .has_aggregate)
      then
        Error (Compile_error.Aggregate_not_allowed "GROUP BY")
      else
        Ok ()
    in
    let%bind () =
      match select.having with
      | None -> Ok ()
      | Some condition -> validate_condition ~validate_subquery ~visible condition
    in
    let order_by = List.map select.order_by ~f:(fun order -> order.Ast.expr) in
    let%bind () = validate_expressions ~validate_subquery ~visible order_by in
    let expressions = select.projection @ order_by in
    let analyses =
      List.map expressions ~f:(fun expression ->
        analyze_expression
          ~sources
          ~groups:select.group_by
          ~inside_aggregate:false
          expression)
      @ Option.value_map select.having ~default:[] ~f:(fun condition ->
        [ analyze_condition
            ~sources
            ~groups:select.group_by
            ~inside_aggregate:false
            condition
        ])
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
        validate_locking select ~aggregate_query)
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

let rec validate_assignments ~validate_subquery ~source_id ~visible = function
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
          let%bind () = validate_expr ~validate_subquery ~visible expression in
          check_sql_types
            ~context:("assignment to " ^ Identifier.to_string assignment.column)
            (Some (packed_sql_type assignment.target_type))
            (expression_sql_type expression)
      in
      validate_assignments ~validate_subquery ~source_id ~visible rest
;;

let columns assignments =
  List.map assignments ~f:(fun assignment -> assignment.Ast.column)
;;

let same_columns left right =
  List.length left = List.length right
  && List.for_all left ~f:(fun column -> List.exists right ~f:(Identifier.equal column))
;;

let validate_insert_rows ~validate_subquery ~source_id rows =
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
            let open Result.Let_syntax in
            let%bind () =
              validate_assignments ~validate_subquery ~source_id ~visible:[] assignments
            in
            ensure_no_assignment_aggregate ~visible:[] "INSERT VALUES" assignments)
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

let validate_conflict ~validate_subquery ~source_id = function
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
         let%bind () =
           validate_assignments ~validate_subquery ~source_id ~visible assignments
         in
         let%bind () =
           ensure_no_assignment_aggregate ~visible "ON CONFLICT DO UPDATE SET" assignments
         in
         match where_ with
         | None -> Ok ()
         | Some condition ->
           let%bind () = validate_condition ~validate_subquery ~visible condition in
           ensure_no_aggregate ~sources:visible "ON CONFLICT DO UPDATE WHERE" condition))
;;

(* Correlated aggregates belong to the DML scope when all their referenced
   sources are DML rows. Local subquery aggregates remain legal. *)
let condition_has_correlated_aggregate ~visible condition =
  (analyze_condition
     ~sources:visible
     ~correlations:true
     ~groups:[]
     ~inside_aggregate:false
     condition)
    .has_aggregate
;;

let assignment_has_correlated_aggregate ~visible assignment =
  match assignment.Ast.value with
  | Ast.Default -> false
  | Ast.Expression expression ->
    (analyze_expression
       ~sources:visible
       ~correlations:true
       ~groups:[]
       ~inside_aggregate:false
       expression)
      .has_aggregate
;;

let validate_merge_assignments
      ~validate_subquery
      ~source_id
      ~visible
      ~branch
      ~action
      assignments
  =
  let open Result.Let_syntax in
  let%bind () =
    if List.is_empty assignments then
      Error (Compile_error.Empty_merge_assignments { branch; action })
    else (
      match
        duplicate_assignment assignments
      with
      | Some column -> Error (Compile_error.Duplicate_assignment column)
      | None -> Ok ())
  in
  let%bind () = validate_assignments ~validate_subquery ~source_id ~visible assignments in
  List.fold assignments ~init:(Ok ()) ~f:(fun result assignment ->
    let%bind () = result in
    match assignment.Ast.value with
    | Ast.Default -> Ok ()
    | Ast.Expression expression ->
      if (analyze_expression ~groups:[] ~inside_aggregate:false expression).has_aggregate
      then
        Error (Compile_error.Aggregate_not_allowed "MERGE assignment")
      else
        Ok ())
;;

let validate_merge ~validate_subquery ~source_id (merge : Ast.merge) =
  let open Result.Let_syntax in
  let visible = [ source_id; merge.using.source_id ] in
  let%bind () = validate_condition ~validate_subquery ~visible merge.on in
  let%bind () = ensure_no_aggregate "MERGE ON" merge.on in
  let%bind () =
    if condition_has_correlated_aggregate ~visible merge.on then
      Error (Compile_error.Aggregate_not_allowed "MERGE ON")
    else
      Ok ()
  in
  let%bind () =
    match merge.using.kind with
    | Ast.Values values -> validate_values ~validate_subquery values
    | Ast.Table _ | Ast.Derived _ | Ast.Cte _ -> Ok ()
  in
  let validate_condition ~visible = function
    | None -> Ok ()
    | Some condition ->
      let%bind () = validate_condition ~validate_subquery ~visible condition in
      ensure_no_aggregate "MERGE WHEN" condition
  in
  let rec branches index matched_terminal not_matched_terminal = function
    | [] -> Ok ()
    | Ast.Matched branch :: rest ->
      let%bind () =
        if matched_terminal then
          Error
            (Compile_error.Unreachable_merge_branch { branch = index; kind = `Matched })
        else
          Ok ()
      in
      let%bind () = validate_condition ~visible branch.condition in
      let%bind () =
        if
          Option.value_map
            branch.condition
            ~default:false
            ~f:(condition_has_correlated_aggregate ~visible)
        then
          Error (Compile_error.Aggregate_not_allowed "MERGE WHEN")
        else
          Ok ()
      in
      let%bind () =
        match branch.action with
        | Ast.Merge_update assignments ->
          let%bind () =
            validate_merge_assignments
              ~validate_subquery
              ~source_id
              ~visible
              ~branch:index
              ~action:`Update
              assignments
          in
          if List.exists assignments ~f:(assignment_has_correlated_aggregate ~visible)
          then
            Error (Compile_error.Aggregate_not_allowed "MERGE UPDATE")
          else
            Ok ()
        | Ast.Merge_delete | Ast.Merge_matched_do_nothing -> Ok ()
      in
      branches (index + 1) (Option.is_none branch.condition) not_matched_terminal rest
    | Ast.Not_matched branch :: rest ->
      let%bind () =
        if not_matched_terminal then
          Error
            (Compile_error.Unreachable_merge_branch
               { branch = index; kind = `Not_matched })
        else
          Ok ()
      in
      let visible = [ merge.using.source_id ] in
      let%bind () = validate_condition ~visible branch.condition in
      let%bind () =
        if
          Option.value_map
            branch.condition
            ~default:false
            ~f:(condition_has_correlated_aggregate ~visible)
        then
          Error (Compile_error.Aggregate_not_allowed "MERGE WHEN")
        else
          Ok ()
      in
      let%bind () =
        match branch.action with
        | Ast.Merge_insert assignments ->
          let%bind () =
            validate_merge_assignments
              ~validate_subquery
              ~source_id
              ~visible
              ~branch:index
              ~action:`Insert
              assignments
          in
          if List.exists assignments ~f:(assignment_has_correlated_aggregate ~visible)
          then
            Error (Compile_error.Aggregate_not_allowed "MERGE INSERT")
          else
            Ok ()
        | Ast.Merge_not_matched_do_nothing -> Ok ()
      in
      branches (index + 1) matched_terminal (Option.is_none branch.condition) rest
  in
  if List.is_empty merge.branches then
    Error Compile_error.Empty_merge_branches
  else
    branches 1 false false merge.branches
;;

let validate_command_with ~validate_subquery (command : Ast.command) =
  match command.Ast.kind with
  | Ast.Merge merge ->
    validate_merge ~validate_subquery ~source_id:command.source.source_id merge
  | Ast.Insert ->
    let open Result.Let_syntax in
    let source_id = command.source.source_id in
    let%bind () =
      match command.insert_input with
      | None -> Error Compile_error.Missing_insert_source
      | Some Ast.Mixed_sources -> Error Compile_error.Mixed_insert_sources
      | Some (Ast.Rows rows) -> validate_insert_rows ~validate_subquery ~source_id rows
      | Some (Ast.Select_rows { columns; query; result_types }) ->
        let%bind () = validate_subquery ~outer_visible:[] ~allow_empty:false query in
        let%bind () =
          if List.is_empty columns then
            Error (Compile_error.Empty_assignments `Insert)
          else
            Ok ()
        in
        let%bind () =
          List.fold columns ~init:(Ok []) ~f:(fun result column ->
            let%bind seen = result in
            if Int.(column.Ast.target_source_id <> source_id) then
              Error
                (Compile_error.Invalid_assignment_source
                   { expected = source_id; actual = column.target_source_id })
            else if List.mem seen column.target_column ~equal:Identifier.equal then
              Error (Compile_error.Duplicate_assignment column.target_column)
            else
              Ok (column.target_column :: seen))
          |> Result.map ~f:(fun _ -> ())
        in
        let expected =
          List.map columns ~f:(fun column ->
            let (Db_type.Pack db_type) = column.Ast.target_type in
            Db_type.fingerprint db_type)
        in
        let actual =
          List.map result_types ~f:(fun (Db_type.Pack db_type) ->
            Db_type.fingerprint db_type)
        in
        if List.equal String.equal expected actual then
          Ok ()
        else
          Error (Compile_error.Mismatched_insert_select_projection { expected; actual })
    in
    (match command.conflict with
     | None -> Ok ()
     | Some conflict -> validate_conflict ~validate_subquery ~source_id conflict)
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
        let%bind () =
          validate_assignments ~validate_subquery ~source_id ~visible command.assignments
        in
        let%bind () =
          ensure_no_assignment_aggregate ~visible "UPDATE SET" command.assignments
        in
        (match command.where_ with
         | None -> Ok ()
         | Some condition ->
           let%bind () = validate_condition ~validate_subquery ~visible condition in
           ensure_no_aggregate ~sources:visible "UPDATE WHERE" condition))
  | Ast.Delete ->
    (match command.where_ with
     | None -> Ok ()
     | Some condition ->
       let visible = [ command.source.source_id ] in
       let open Result.Let_syntax in
       let%bind () = validate_condition ~validate_subquery ~visible condition in
       ensure_no_aggregate ~sources:visible "DELETE WHERE" condition)
;;

let fingerprints types =
  List.map types ~f:(fun (Db_type.Pack db_type) -> Db_type.fingerprint db_type)
;;

let validate_output_schema columns ~column_types ~result_types =
  let open Result.Let_syntax in
  let%bind names =
    List.mapi columns ~f:(fun index -> function
      | Ast.Column { name; _ } -> Ok name
      | _ -> Error (Compile_error.Invalid_relation_column (index + 1)))
    |> Result.all
  in
  let rec duplicate seen = function
    | [] -> None
    | name :: rest ->
      if List.mem seen name ~equal:Identifier.equal then
        Some name
      else
        duplicate (name :: seen) rest
  in
  let%bind () =
    match duplicate [] names with
    | None -> Ok ()
    | Some name -> Error (Compile_error.Duplicate_relation_column name)
  in
  let expected = fingerprints column_types in
  let actual = fingerprints result_types in
  if List.equal String.equal expected actual then
    Ok ()
  else
    Error (Compile_error.Mismatched_relation_projection { expected; actual })
;;

let validate_type_vectors ~error left right =
  let expected = fingerprints left in
  let actual = fingerprints right in
  if List.equal String.equal expected actual then
    Ok ()
  else
    Error (error ~expected ~actual)
;;

let validate_relation_schema (relation : Ast.relation) =
  validate_output_schema
    relation.Ast.columns
    ~column_types:relation.column_types
    ~result_types:relation.result_types
;;

let rec select_query_output_field_names = function
  | Ast.Simple select ->
    List.map select.Ast.projection ~f:(function
      | Ast.Column { name; _ } -> Some name
      | _ -> None)
  | Ast.Source_free _ -> [ None ]
  | Ast.Compound compound -> select_query_output_field_names compound.left
;;

let rec validate_select_query_full
          ?(top_level = false)
          ?(outer_visible = [])
          ?(allow_empty = false)
          ~forbidden_ctes
          ~available_ctes
  = function
  | Ast.Simple select ->
    validate_select_full
      ~top_level
      ~outer_visible
      ~allow_empty
      ~forbidden_ctes
      ~available_ctes
      select
  | Ast.Source_free source_free ->
    let open Result.Let_syntax in
    let%bind available_ctes =
      validate_ctes_full ~top_level ~forbidden_ctes ~available_ctes source_free.ctes
    in
    let validate_subquery ~outer_visible ~allow_empty query =
      validate_select_query_full
        ~forbidden_ctes
        ~available_ctes
        ~outer_visible
        ~allow_empty
        query
    in
    let%bind () =
      validate_expr ~validate_subquery ~visible:outer_visible source_free.expression
    in
    let analysis =
      analyze_expression ~groups:[] ~inside_aggregate:false source_free.expression
    in
    if analysis.nested_aggregate then
      Error Compile_error.Nested_aggregate
    else
      Ok ()
  | Ast.Compound compound ->
    let open Result.Let_syntax in
    let%bind () =
      let locked = function
        | Ast.Simple select -> Option.is_some select.Ast.locking
        | Ast.Source_free _ | Ast.Compound _ -> false
      in
      if locked compound.left || locked compound.right then
        Error (Compile_error.Invalid_for_update "cannot be used in a set operation")
      else
        Ok ()
    in
    let%bind available_ctes =
      validate_ctes_full ~top_level ~forbidden_ctes ~available_ctes compound.ctes
    in
    let%bind () =
      validate_type_vectors
        ~error:(fun ~expected ~actual ->
          Compile_error.Mismatched_set_projection { expected; actual })
        compound.left_types
        compound.right_types
    in
    let%bind () =
      let output_fields = select_query_output_field_names compound.left in
      List.fold compound.order_by ~init:(Ok ()) ~f:(fun result order ->
        let%bind () = result in
        let matches =
          List.count output_fields ~f:(function
            | Some field -> Identifier.equal field order.Ast.field
            | None -> false)
        in
        if Int.equal matches 1 then
          Ok ()
        else
          Error
            (Compile_error.Invalid_set_order_field
               { field = Identifier.to_string order.field; matches }))
    in
    let%bind () =
      validate_select_query_full
        ~outer_visible
        ~forbidden_ctes
        ~available_ctes
        compound.left
    in
    validate_select_query_full
      ~outer_visible
      ~forbidden_ctes
      ~available_ctes
      compound.right

and validate_select_full
      ~top_level
      ~outer_visible
      ~allow_empty
      ~forbidden_ctes
      ~available_ctes
      select
  =
  let open Result.Let_syntax in
  let%bind available_ctes =
    validate_ctes_full ~top_level ~forbidden_ctes ~available_ctes select.Ast.ctes
  in
  let%bind () = validate_source_full ~forbidden_ctes ~available_ctes select.source in
  let%bind () =
    List.fold select.joins ~init:(Ok ()) ~f:(fun result join ->
      let%bind () = result in
      validate_source_full ~forbidden_ctes ~available_ctes join.Ast.source)
  in
  let validate_subquery ~outer_visible ~allow_empty query =
    validate_select_query_full
      ~forbidden_ctes
      ~available_ctes
      ~outer_visible
      ~allow_empty
      query
  in
  validate_select_with ~validate_subquery ~outer_visible ~allow_empty select

and validate_source_full ~forbidden_ctes ~available_ctes source =
  match source.Ast.kind with
  | Ast.Table _ -> Ok ()
  | Ast.Values _ -> Ok ()
  | Ast.Cte id ->
    if List.mem forbidden_ctes id ~equal:Int.equal then
      Error (Compile_error.Invalid_recursive_reference id)
    else if List.mem available_ctes id ~equal:Int.equal then
      Ok ()
    else
      Error (Compile_error.Unknown_cte id)
  | Ast.Derived relation ->
    validate_relation_full ~forbidden_ctes ~available_ctes relation

and validate_relation_full ~forbidden_ctes ~available_ctes relation =
  let open Result.Let_syntax in
  let%bind () = validate_relation_schema relation in
  validate_select_query_full ~forbidden_ctes ~available_ctes relation.query

and validate_ctes_full ?(top_level = false) ~forbidden_ctes ~available_ctes ctes =
  List.fold ctes ~init:(Ok available_ctes) ~f:(fun result cte ->
    let open Result.Let_syntax in
    let%bind available_ctes = result in
    let%bind () =
      match cte.Ast.body with
      | (Ast.Returning_body _ | Ast.Command_body _) when not top_level ->
        Error Compile_error.Invalid_cte_placement
      | Ast.Select_body _
      | Ast.Recursive_body _
      | Ast.Returning_body _
      | Ast.Command_body _ -> Ok ()
    in
    let%map () = validate_cte_full ~forbidden_ctes ~available_ctes cte in
    available_ctes @ [ cte.Ast.cte_id ])

and validate_cte_full ~forbidden_ctes ~available_ctes cte =
  let open Result.Let_syntax in
  let%bind () =
    match cte.Ast.body with
    | Ast.Command_body _ when List.is_empty cte.columns -> Ok ()
    | _ ->
      validate_output_schema
        cte.columns
        ~column_types:cte.column_types
        ~result_types:cte.result_types
  in
  match cte.body with
  | Ast.Select_body query ->
    validate_select_query_full ~forbidden_ctes ~available_ctes query
  | Ast.Recursive_body { anchor; step; _ } ->
    let%bind () = validate_relation_full ~forbidden_ctes ~available_ctes anchor in
    let%bind () =
      validate_type_vectors
        ~error:(fun ~expected ~actual ->
          Compile_error.Mismatched_relation_projection { expected; actual })
        cte.result_types
        anchor.result_types
    in
    let%bind () =
      validate_recursive_step ~forbidden_ctes ~available_ctes ~cte_id:cte.cte_id step
    in
    validate_type_vectors
      ~error:(fun ~expected ~actual ->
        Compile_error.Mismatched_set_projection { expected; actual })
      anchor.result_types
      step.result_types
  | Ast.Returning_body returning ->
    validate_returning_full ~forbidden_ctes ~available_ctes returning
  | Ast.Command_body command ->
    validate_command_full ~forbidden_ctes ~available_ctes command

and validate_recursive_step ~forbidden_ctes ~available_ctes ~cte_id step =
  let open Result.Let_syntax in
  let%bind () = validate_relation_schema step in
  match step.Ast.query with
  | Ast.Compound _ | Ast.Source_free _ ->
    Error (Compile_error.Invalid_recursive_reference cte_id)
  | Ast.Simple select ->
    let%bind available_ctes =
      validate_ctes_full ~forbidden_ctes ~available_ctes select.ctes
    in
    let sources =
      select.source :: List.map select.joins ~f:(fun join -> join.Ast.source)
    in
    let is_self (source : Ast.source) =
      match source.Ast.kind with
      | Ast.Cte id -> Int.equal id cte_id
      | Ast.Table _ | Ast.Derived _ | Ast.Values _ -> false
    in
    let nullable_self =
      List.exists select.joins ~f:(fun join ->
        is_self join.Ast.source
        &&
        match join.operation with
        | Ast.Predicate (Ast.Left, _) -> true
        | Ast.Predicate (Ast.Inner, _) | Ast.Cross -> false)
    in
    let source_ids = List.map sources ~f:(fun source -> source.Ast.source_id) in
    let has_aggregate =
      List.exists
        (select.projection
         @ select.group_by
         @ List.map select.order_by ~f:(fun order -> order.Ast.expr))
        ~f:(Aggregate_scope.expression_has_local_aggregate ~sources:source_ids)
      || Option.exists
           select.having
           ~f:(Aggregate_scope.condition_has_local_aggregate ~sources:source_ids)
    in
    if has_aggregate then
      Error (Compile_error.Aggregate_not_allowed "recursive term")
    else if nullable_self || not (Int.equal (List.count sources ~f:is_self) 1) then
      Error (Compile_error.Invalid_recursive_reference cte_id)
    else (
      let forbidden_ctes = cte_id :: forbidden_ctes in
      let validate_source result source =
        let%bind () = result in
        if is_self source then
          Ok ()
        else
          validate_source_full ~forbidden_ctes ~available_ctes source
      in
      let%bind () = List.fold sources ~init:(Ok ()) ~f:validate_source in
      let validate_subquery ~outer_visible ~allow_empty query =
        validate_select_query_full
          ~forbidden_ctes
          ~available_ctes
          ~outer_visible
          ~allow_empty
          query
      in
      validate_select_with ~validate_subquery ~outer_visible:[] ~allow_empty:false select)

and validate_returning_full ?(top_level = false) ~forbidden_ctes ~available_ctes returning
  =
  let open Result.Let_syntax in
  let%bind () =
    validate_command_full ~top_level ~forbidden_ctes ~available_ctes returning.Ast.command
  in
  let available_ctes =
    available_ctes @ List.map returning.command.ctes ~f:(fun cte -> cte.Ast.cte_id)
  in
  let visible =
    match returning.command.kind with
    | Ast.Merge merge -> [ returning.command.source.source_id; merge.using.source_id ]
    | Ast.Insert | Ast.Update | Ast.Delete -> [ returning.command.source.source_id ]
  in
  let validate_subquery ~outer_visible ~allow_empty query =
    validate_select_query_full
      ~forbidden_ctes
      ~available_ctes
      ~outer_visible
      ~allow_empty
      query
  in
  let%bind () = validate_expressions ~validate_subquery ~visible returning.projection in
  let clause =
    match returning.command.kind with
    | Ast.Insert -> "INSERT RETURNING"
    | Ast.Update -> "UPDATE RETURNING"
    | Ast.Delete -> "DELETE RETURNING"
    | Ast.Merge _ -> "MERGE RETURNING"
  in
  if
    List.exists returning.projection ~f:(fun expression ->
      (analyze_expression ~sources:visible ~groups:[] ~inside_aggregate:false expression)
        .has_aggregate)
  then
    Error (Compile_error.Aggregate_not_allowed clause)
  else
    Ok ()

and validate_command_full ?(top_level = false) ~forbidden_ctes ~available_ctes command =
  let open Result.Let_syntax in
  let%bind () =
    match command.Ast.source.kind with
    | Ast.Table _ -> Ok ()
    | Ast.Derived _ | Ast.Values _ | Ast.Cte _ ->
      Error Compile_error.Invalid_command_target
  in
  let%bind () =
    match command.kind with
    | Ast.Insert | Ast.Update | Ast.Delete -> Ok ()
    | Ast.Merge merge ->
      if
        not
          (List.is_empty command.assignments
           && List.is_empty command.from
           && Option.is_none command.insert_input
           && Option.is_none command.conflict
           && Option.is_none command.where_)
      then
        Error (Compile_error.Invalid_merge "unrelated command fields must be empty")
      else if Int.equal command.source.source_id merge.using.source_id then
        Error
          (Compile_error.Invalid_merge "target and source must have distinct identities")
      else if
        List.exists command.ctes ~f:(fun cte ->
          match cte.Ast.body with
          | Ast.Recursive_body _ -> true
          | Ast.Select_body _ | Ast.Returning_body _ | Ast.Command_body _ -> false)
      then
        Error
          (Compile_error.Invalid_merge "WITH RECURSIVE is not supported directly by MERGE")
      else
        Ok ()
  in
  let%bind available_ctes =
    validate_ctes_full ~top_level ~forbidden_ctes ~available_ctes command.Ast.ctes
  in
  let%bind () =
    match command.kind with
    | Ast.Merge merge -> validate_source_full ~forbidden_ctes ~available_ctes merge.using
    | Ast.Insert | Ast.Update | Ast.Delete -> Ok ()
  in
  let%bind () = validate_source_full ~forbidden_ctes ~available_ctes command.source in
  let%bind () =
    List.fold command.from ~init:(Ok ()) ~f:(fun result source ->
      let%bind () = result in
      validate_source_full ~forbidden_ctes ~available_ctes source)
  in
  let validate_subquery ~outer_visible ~allow_empty query =
    validate_select_query_full
      ~forbidden_ctes
      ~available_ctes
      ~outer_visible
      ~allow_empty
      query
  in
  validate_command_with ~validate_subquery command
;;

let result_query = function
  | Ast.Select query ->
    validate_select_query_full ~top_level:true ~forbidden_ctes:[] ~available_ctes:[] query
  | Ast.Returning returning ->
    let open Result.Let_syntax in
    let%bind () =
      validate_returning_full
        ~top_level:true
        ~forbidden_ctes:[]
        ~available_ctes:[]
        returning
    in
    if List.is_empty returning.projection then
      Error Compile_error.Empty_projection
    else
      Ok ()
;;

let command command =
  validate_command_full ~top_level:true ~forbidden_ctes:[] ~available_ctes:[] command
;;
