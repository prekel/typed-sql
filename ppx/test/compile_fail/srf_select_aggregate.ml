(* expected: set-returning functions are not allowed in this clause *)
open! Base

let query conn = [%pgsql conn "SELECT sum(generate_series(1,3))"]
