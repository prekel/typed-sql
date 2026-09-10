open! Base

type t =
  | Empty_projection
  | Foreign_source of
      { expected : int
      ; actual : int
      }
  | Negative_limit of int
  | Negative_offset of int

let to_string = function
  | Empty_projection -> "SELECT projection must contain at least one expression"
  | Foreign_source { expected; actual } ->
    String.concat
      [ "expression references source #"
      ; Int.to_string actual
      ; ", but this query exposes source #"
      ; Int.to_string expected
      ]
  | Negative_limit value -> "LIMIT must be non-negative, got " ^ Int.to_string value
  | Negative_offset value -> "OFFSET must be non-negative, got " ^ Int.to_string value
;;

let pp formatter error = Stdlib.Format.pp_print_string formatter (to_string error)
