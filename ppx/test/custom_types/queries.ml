open! Base

type value = Typ123 of string

type mood =
  | Ready
  | Done

type point = Point123 of int * int

let equal_value (Typ123 left) (Typ123 right) = String.equal left right

let equal_mood left right =
  match left, right with
  | Ready, Ready | Done, Done -> true
  | _ -> false
;;

let equal_point (Point123 (lx, ly)) (Point123 (rx, ry)) = Int.(lx = rx && ly = ry)

module PGOCaml = struct
  include PGOCaml

  let string_of_typ123 (Typ123 value) = value
  let typ123_of_string value = Typ123 value

  let string_of_mood123 = function
    | Ready -> "ready"
    | Done -> "done"
  ;;

  let mood123_of_string = function
    | "ready" -> Ready
    | "done" -> Done
    | value -> Stdlib.raise (Error ("unexpected mood: " ^ value))
  ;;

  let string_of_point123 (Point123 (x, y)) = Printf.sprintf "(%d,%d)" x y

  let point123_of_string value =
    Stdlib.Scanf.sscanf value "(%d,%d)" (fun x y -> Point123 (x, y))
  ;;
end

let domain conn (value : value option) : string option list =
  [%pgsql conn "SELECT $?value::custom_type_test.typ123"]
;;

let array conn (values : value option list option) : value option list option list =
  [%pgsql conn "SELECT $?values::custom_type_test.typ123[]"]
;;

let enum conn (value : mood option) : mood option list =
  [%pgsql conn "SELECT $?value::custom_type_test.mood123"]
;;

let composite conn (value : point option) : point option list =
  [%pgsql conn "SELECT $?value::custom_type_test.point123"]
;;

let object_row conn (value : value option list) =
  [%pgsql.object
    conn "SELECT value, optional_value FROM custom_type_test.items WHERE value = $value"]
;;
