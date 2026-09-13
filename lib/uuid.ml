open! Base

type t = string

let is_hex = function
  | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
  | _ -> false
;;

let is_valid value =
  Int.(String.length value = 36)
  && List.for_all [ 8; 13; 18; 23 ] ~f:(fun index -> Char.equal value.[index] '-')
  && String.for_alli value ~f:(fun index character ->
    if List.mem [ 8; 13; 18; 23 ] index ~equal:Int.equal then
      Char.equal character '-'
    else
      is_hex character)
;;

let of_string value =
  if is_valid value then
    Some (String.lowercase value)
  else
    None
;;

let of_string_exn value =
  match of_string value with
  | Some uuid -> uuid
  | None -> Stdlib.invalid_arg "invalid UUID"
;;

let to_string value = value
let equal = String.equal
