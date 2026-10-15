(* expected: Types for method count are incompatible *)
open! Base

let query conn : < count : int64 > list =
  [%pgsql.object conn "SELECT count(*) AS count FROM join_people"]
;;
