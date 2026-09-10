open! Base

type t = string

type error =
  [ `Empty
  | `Contains_nul
  ]

let error_to_string = function
  | `Empty -> "SQL identifier must not be empty"
  | `Contains_nul -> "SQL identifier must not contain a NUL byte"
;;

let of_string value =
  if String.is_empty value then
    Error `Empty
  else if String.exists value ~f:(Char.equal '\000') then
    Error `Contains_nul
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
