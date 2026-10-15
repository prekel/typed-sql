(* expected: Types for method position are incompatible *)
open! Base

let query conn : < position : int64 > list =
  [%pgsql.object conn "SELECT row_number() OVER() AS position FROM join_people"]
;;
