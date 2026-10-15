(* expected: expected ON *)
open! Base

let query conn =
  [%pgsql conn "SELECT p.id FROM join_people p JOIN join_links l WHERE true"]
;;
