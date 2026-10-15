(* expected: duplicate object method name: id *)
open! Base

let query conn =
  [%pgsql.object
    conn "SELECT p.*, l.* FROM join_people p JOIN join_links l ON p.id = l.person_id"]
;;
