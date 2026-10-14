(* expected: duplicate pagination clause *)
open! Base

let query conn = [%pgsql conn "SELECT id FROM people LIMIT 1 OFFSET 0 LIMIT 2"]
