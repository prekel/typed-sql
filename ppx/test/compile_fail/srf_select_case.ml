(* expected: set-returning functions are not allowed in CASE *)
open! Base

let query conn = [%pgsql conn "SELECT CASE WHEN true THEN generate_series(1,3) END"]
