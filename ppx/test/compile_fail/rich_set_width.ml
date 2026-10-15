(* expected: equal column counts *)
open! Base

let query conn =
  [%pgsql conn "SELECT id, name FROM join_people UNION SELECT id FROM join_links"]
;;
