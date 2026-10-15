(* expected: column qualifier does not name the statement source *)
open! Base

let query conn =
  [%pgsql
    conn
      "SELECT p.id FROM join_people p JOIN join_links l ON other.id = l.person_id JOIN join_people other ON other.id = p.id"]
;;
