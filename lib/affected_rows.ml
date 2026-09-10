open! Base

type t =
  | Known of int
  | Unknown

let pp formatter = function
  | Known count -> Stdlib.Format.pp_print_int formatter count
  | Unknown -> Stdlib.Format.pp_print_string formatter "unknown"
;;
