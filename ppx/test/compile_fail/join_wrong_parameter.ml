(* expected: int32 *)
open! Base

let query conn (value : string) =
  [%pgsql
    conn
      "SELECT p.id FROM join_people p JOIN join_links l ON p.id = l.person_id AND l.id = $value"]
;;
