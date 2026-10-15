(* expected: ambiguous column: id *)
open! Base

let query conn =
  [%pgsql conn "SELECT id FROM join_people p JOIN join_links l ON p.id = l.person_id"]
;;
