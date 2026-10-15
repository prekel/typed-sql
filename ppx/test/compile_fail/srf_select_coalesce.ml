(* expected: set-returning functions are not allowed in COALESCE *)
open! Base

let query conn = [%pgsql conn "SELECT coalesce(generate_series(1,3),0)"]
