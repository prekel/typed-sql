(* expected: PostgreSQL json has no equality operator *)
open! Base

let query conn =
  let document = "{}" in
  [%pgsql conn {|SELECT id FROM people WHERE document = $document|}]
;;
