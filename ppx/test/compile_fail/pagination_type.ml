(* expected: expected of type int64 *)
open! Base

let query conn =
  let limit = 1l in
  [%pgsql conn "SELECT id FROM people LIMIT $limit"]
;;
