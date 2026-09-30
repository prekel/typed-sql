open! Base

type t =
  | Empty_projection
  | Empty_values_columns
  | Empty_values_rows
  | Foreign_source of
      { visible : int list
      ; actual : int
      }
  | Negative_limit of int
  | Negative_fetch_count of int
  | Negative_offset of int
  | Fetch_with_ties_requires_order_by
  | Invalid_for_update of string
  | Empty_assignments of [ `Insert | `Update ]
  | Empty_insert_row of int
  | Duplicate_assignment of Identifier.t
  | Mismatched_insert_columns of
      { row : int
      ; expected : Identifier.t list
      ; actual : Identifier.t list
      }
  | Missing_insert_source
  | Mixed_insert_sources
  | Mismatched_insert_select_projection of
      { expected : string list
      ; actual : string list
      }
  | Empty_conflict_target
  | Duplicate_conflict_target of Identifier.t
  | Invalid_conflict_target_source of
      { expected : int
      ; actual : int
      }
  | Empty_conflict_update
  | Invalid_assignment_source of
      { expected : int
      ; actual : int
      }
  | Unsupported_operation of
      { operation : string
      ; dialect : Dialect.t
      }
  | Aggregate_not_allowed of string
  | Nested_aggregate
  | Ungrouped_expression
  | Scalar_subquery_may_return_many_rows
  | Exactly_one_query_not_proven
  | Invalid_relation_column of int
  | Duplicate_relation_column of Identifier.t
  | Mismatched_relation_projection of
      { expected : string list
      ; actual : string list
      }
  | Mismatched_set_projection of
      { expected : string list
      ; actual : string list
      }
  | Invalid_set_order_field of
      { field : string
      ; matches : int
      }
  | Mismatched_values_row_arity of
      { row : int
      ; expected : int
      ; actual : int
      }
  | Mismatched_values_row_types of
      { row : int
      ; expected : string list
      ; actual : string list
      }
  | Unknown_cte of int
  | Invalid_recursive_reference of int
  | Unsupported_multiset_field_type of
      { path : int list
      ; type_name : string
      }

let to_string = function
  | Empty_projection -> "SELECT projection must contain at least one expression"
  | Empty_values_columns -> "VALUES relation must declare at least one column"
  | Empty_values_rows -> "VALUES relation must contain at least one row"
  | Foreign_source { visible; actual } ->
    String.concat
      [ "expression references source #"
      ; Int.to_string actual
      ; ", but the visible sources are "
      ; List.map visible ~f:Int.to_string |> String.concat ~sep:", "
      ]
  | Negative_limit value -> "LIMIT must be non-negative, got " ^ Int.to_string value
  | Negative_fetch_count value ->
    "FETCH FIRST row count must be non-negative, got " ^ Int.to_string value
  | Negative_offset value -> "OFFSET must be non-negative, got " ^ Int.to_string value
  | Fetch_with_ties_requires_order_by -> "FETCH FIRST WITH TIES requires ORDER BY"
  | Invalid_for_update reason -> "FOR UPDATE " ^ reason
  | Empty_assignments `Insert -> "INSERT must assign at least one column"
  | Empty_assignments `Update -> "UPDATE must assign at least one column"
  | Empty_insert_row row -> "INSERT row " ^ Int.to_string row ^ " has no assignments"
  | Duplicate_assignment column ->
    "column " ^ Identifier.to_string column ^ " is assigned more than once"
  | Mismatched_insert_columns { row; expected; actual } ->
    let columns columns =
      List.map columns ~f:Identifier.to_string |> String.concat ~sep:", "
    in
    String.concat
      [ "INSERT row "
      ; Int.to_string row
      ; " assigns columns ["
      ; columns actual
      ; "], expected ["
      ; columns expected
      ; "]"
      ]
  | Missing_insert_source -> "INSERT has no row source"
  | Mixed_insert_sources -> "INSERT cannot combine VALUES and SELECT sources"
  | Mismatched_insert_select_projection { expected; actual } ->
    "INSERT target types ["
    ^ String.concat ~sep:", " expected
    ^ "] do not match SELECT types ["
    ^ String.concat ~sep:", " actual
    ^ "]"
  | Empty_conflict_target -> "ON CONFLICT target must contain at least one column"
  | Duplicate_conflict_target column ->
    Stdlib.Format.asprintf
      "ON CONFLICT target contains column %s more than once"
      (Identifier.to_string column)
  | Invalid_conflict_target_source { expected; actual } ->
    String.concat
      [ "ON CONFLICT target column belongs to source #"
      ; Int.to_string actual
      ; ", expected source #"
      ; Int.to_string expected
      ]
  | Empty_conflict_update -> "ON CONFLICT DO UPDATE must assign at least one column"
  | Invalid_assignment_source { expected; actual } ->
    String.concat
      [ "assignment belongs to source #"
      ; Int.to_string actual
      ; ", but the command targets source #"
      ; Int.to_string expected
      ]
  | Unsupported_operation { operation; dialect } ->
    operation ^ " is not supported by the " ^ Dialect.to_string dialect ^ " dialect"
  | Aggregate_not_allowed clause -> "aggregate expressions are not allowed in " ^ clause
  | Nested_aggregate -> "aggregate expressions cannot be nested"
  | Ungrouped_expression -> "non-aggregate expression must be present in GROUP BY"
  | Scalar_subquery_may_return_many_rows ->
    "scalar subquery requires LIMIT 0/1 or a local aggregate without GROUP BY"
  | Exactly_one_query_not_proven ->
    "exactly-one SELECT requires an ungrouped aggregate without HAVING, OFFSET, or row limit 0"
  | Invalid_relation_column position ->
    "relation output #" ^ Int.to_string position ^ " must be a direct descriptor column"
  | Duplicate_relation_column column ->
    "relation output column " ^ Identifier.to_string column ^ " occurs more than once"
  | Mismatched_relation_projection { expected; actual } ->
    "relation output types ["
    ^ String.concat ~sep:", " expected
    ^ "] do not match SELECT types ["
    ^ String.concat ~sep:", " actual
    ^ "]"
  | Mismatched_set_projection { expected; actual } ->
    "set operation left types ["
    ^ String.concat ~sep:", " expected
    ^ "] do not match right types ["
    ^ String.concat ~sep:", " actual
    ^ "]"
  | Invalid_set_order_field { field; matches } ->
    "set operation ORDER BY field "
    ^ field
    ^ " matches "
    ^ Int.to_string matches
    ^ " output fields; expected exactly one"
  | Mismatched_values_row_arity { row; expected; actual } ->
    "VALUES row "
    ^ Int.to_string row
    ^ " has "
    ^ Int.to_string actual
    ^ " fields, expected "
    ^ Int.to_string expected
  | Mismatched_values_row_types { row; expected; actual } ->
    "VALUES row "
    ^ Int.to_string row
    ^ " has types ["
    ^ String.concat ~sep:", " actual
    ^ "], expected ["
    ^ String.concat ~sep:", " expected
    ^ "]"
  | Unknown_cte id -> "query references unavailable CTE #" ^ Int.to_string id
  | Invalid_recursive_reference id ->
    "recursive term must reference CTE #"
    ^ Int.to_string id
    ^ " exactly once as a top-level source"
  | Unsupported_multiset_field_type { path; type_name } ->
    "multiset field "
    ^ (List.map path ~f:Int.to_string |> String.concat ~sep:".")
    ^ " has unsupported database type "
    ^ type_name
;;

let pp formatter error = Stdlib.Format.pp_print_string formatter (to_string error)
