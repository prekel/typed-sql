(* expected: cannot infer parameter type without a SQL context *)
open! Base

let query conn ids = [%pgsql conn "SELECT * FROM unnest($ids)"]
