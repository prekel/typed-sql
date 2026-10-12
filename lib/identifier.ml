open! Base

type t = string [@@deriving sexp_of]

type error =
  [ `Empty
  | `Contains_nul
  | `Too_long of int
  ]
[@@deriving sexp_of]

let error_to_string = function
  | `Empty -> "SQL identifier must not be empty"
  | `Contains_nul -> "SQL identifier must not contain a NUL byte"
  | `Too_long length ->
    "SQL identifier must be at most 63 bytes, got " ^ Int.to_string length
;;

let of_string value =
  if String.is_empty value then
    Error `Empty
  else if String.exists value ~f:(Char.equal '\000') then
    Error `Contains_nul
  else if Int.(String.length value > 63) then
    Error (`Too_long (String.length value))
  else
    Ok value
;;

let of_string_exn value =
  match of_string value with
  | Ok identifier -> identifier
  | Error error -> Stdlib.invalid_arg (error_to_string error)
;;

let to_string value = value
let equal = String.equal
let pp formatter value = Stdlib.Format.pp_print_string formatter value
