(* expected: set-returning functions are not allowed in this clause *)
open! Base

let query conn =
  [%pgsql conn "SELECT * FROM ROWS FROM(generate_series(1,generate_series(1,3))) q"]
;;
