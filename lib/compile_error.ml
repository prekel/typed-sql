open! Base

type t =
  | Empty_projection
  | Foreign_source of
      { visible : int list
      ; actual : int
      }
  | Negative_limit of int
  | Negative_offset of int
  | Empty_assignments of [ `Insert | `Update ]
  | Empty_insert_row of int
  | Duplicate_assignment of Identifier.t
  | Mismatched_insert_columns of
      { row : int
      ; expected : Identifier.t list
      ; actual : Identifier.t list
      }
  | Invalid_assignment_source of
      { expected : int
      ; actual : int
      }
  | Unsupported_operation of
      { operation : string
      ; dialect : Dialect.t
      }

let to_string = function
  | Empty_projection -> "SELECT projection must contain at least one expression"
  | Foreign_source { visible; actual } ->
    String.concat
      [ "expression references source #"
      ; Int.to_string actual
      ; ", but the visible sources are "
      ; List.map visible ~f:Int.to_string |> String.concat ~sep:", "
      ]
  | Negative_limit value -> "LIMIT must be non-negative, got " ^ Int.to_string value
  | Negative_offset value -> "OFFSET must be non-negative, got " ^ Int.to_string value
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
  | Invalid_assignment_source { expected; actual } ->
    String.concat
      [ "assignment belongs to source #"
      ; Int.to_string actual
      ; ", but the command targets source #"
      ; Int.to_string expected
      ]
  | Unsupported_operation { operation; dialect } ->
    operation ^ " is not supported by the " ^ Dialect.to_string dialect ^ " dialect"
;;

let pp formatter error = Stdlib.Format.pp_print_string formatter (to_string error)
