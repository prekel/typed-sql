(* expected: incompatible PostgreSQL result types *)
open! Base

let query conn =
  [%pgsql conn "SELECT CASE WHEN true THEN name ELSE id END FROM join_people"]
;;
