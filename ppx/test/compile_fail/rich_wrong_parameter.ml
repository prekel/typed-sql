(* expected: int64 *)
open! Base

let query conn (minimum : string) =
  [%pgsql conn "SELECT count(*) FROM join_people HAVING count(*) > $minimum"]
;;
