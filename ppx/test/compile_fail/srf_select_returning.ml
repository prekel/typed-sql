(* expected: set-returning functions are not allowed in this clause *)
open! Base

let query conn = [%pgsql conn "DELETE FROM group_keys RETURNING generate_series(1,3)"]
