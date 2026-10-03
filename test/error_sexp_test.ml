open! Base
open Typed_sql

let%test_module "compile error S-expressions" =
  (module struct
    let column = Identifier.of_string_exn "id"

    let print_errors errors =
      Stdio.print_s (Sexp.List (List.map errors ~f:Compile_error.sexp_of_t))
    ;;

    let%test "malformed command errors retain readable messages" =
      String.equal
        (Compile_error.to_string Compile_error.Invalid_command_target)
        "command target must be a base table"
      && String.equal
           (Compile_error.to_string Compile_error.Missing_insert_source)
           "INSERT has no row source"
    ;;

    let%expect_test "query and general compilation errors" =
      print_errors
        [ Compile_error.Empty_projection
        ; Empty_values_columns
        ; Empty_values_rows
        ; Foreign_source { visible = [ 1; 2 ]; actual = 3 }
        ; Negative_limit (-1)
        ; Negative_fetch_count (-2)
        ; Negative_offset (-3)
        ; Fetch_with_ties_requires_order_by
        ; Invalid_for_update "with DISTINCT"
        ; Invalid_command_target
        ; Unsupported_operation { operation = "RETURNING"; dialect = Dialect.Postgresql }
        ; Aggregate_not_allowed "WHERE"
        ; Nested_aggregate
        ; Ungrouped_expression
        ; Scalar_subquery_may_return_many_rows
        ; Exactly_one_query_not_proven
        ];
      [%expect
        {|
        (Empty_projection Empty_values_columns Empty_values_rows
         (Foreign_source (visible (1 2)) (actual 3)) (Negative_limit -1)
         (Negative_fetch_count -2) (Negative_offset -3)
         Fetch_with_ties_requires_order_by (Invalid_for_update "with DISTINCT")
         Invalid_command_target
         (Unsupported_operation (operation RETURNING) (dialect Postgresql))
         (Aggregate_not_allowed WHERE) Nested_aggregate Ungrouped_expression
         Scalar_subquery_may_return_many_rows Exactly_one_query_not_proven)
        |}]
    ;;

    let%expect_test "command compilation errors" =
      print_errors
        [ Compile_error.Empty_assignments `Insert
        ; Empty_assignments `Update
        ; Empty_insert_row 1
        ; Duplicate_assignment column
        ; Mismatched_insert_columns
            { row = 2; expected = [ column ]; actual = [ column; column ] }
        ; Missing_insert_source
        ; Mixed_insert_sources
        ; Mismatched_insert_select_projection
            { expected = [ "integer" ]; actual = [ "text" ] }
        ; Empty_conflict_target
        ; Duplicate_conflict_target column
        ; Invalid_conflict_target_source { expected = 1; actual = 2 }
        ; Empty_conflict_update
        ; Invalid_assignment_source { expected = 1; actual = 2 }
        ];
      [%expect
        {|
        ((Empty_assignments Insert) (Empty_assignments Update) (Empty_insert_row 1)
         (Duplicate_assignment id)
         (Mismatched_insert_columns (row 2) (expected (id)) (actual (id id)))
         Missing_insert_source Mixed_insert_sources
         (Mismatched_insert_select_projection (expected (integer)) (actual (text)))
         Empty_conflict_target (Duplicate_conflict_target id)
         (Invalid_conflict_target_source (expected 1) (actual 2))
         Empty_conflict_update (Invalid_assignment_source (expected 1) (actual 2)))
        |}]
    ;;

    let%expect_test "relation and set compilation errors" =
      print_errors
        [ Compile_error.Invalid_relation_column 1
        ; Duplicate_relation_column column
        ; Mismatched_relation_projection { expected = [ "integer" ]; actual = [ "text" ] }
        ; Mismatched_set_projection { expected = [ "integer" ]; actual = [ "text" ] }
        ; Invalid_set_order_field { field = "id"; matches = 2 }
        ; Mismatched_values_row_arity { row = 1; expected = 2; actual = 1 }
        ; Mismatched_values_row_types
            { row = 1; expected = [ "integer" ]; actual = [ "text" ] }
        ; Unknown_cte 4
        ; Invalid_recursive_reference 5
        ; Unsupported_multiset_field_type { path = [ 1; 2 ]; type_name = "bytes" }
        ];
      [%expect
        {|
        ((Invalid_relation_column 1) (Duplicate_relation_column id)
         (Mismatched_relation_projection (expected (integer)) (actual (text)))
         (Mismatched_set_projection (expected (integer)) (actual (text)))
         (Invalid_set_order_field (field id) (matches 2))
         (Mismatched_values_row_arity (row 1) (expected 2) (actual 1))
         (Mismatched_values_row_types (row 1) (expected (integer)) (actual (text)))
         (Unknown_cte 4) (Invalid_recursive_reference 5)
         (Unsupported_multiset_field_type (path (1 2)) (type_name bytes)))
        |}]
    ;;
  end)
;;
