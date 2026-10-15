(* expected: unknown column *)
open! Base

let query conn = [%pgsql conn "SELECT count(*) OVER(ROWS id PRECEDING) FROM join_people"]
