(* expected: cannot infer parameter type without a SQL context *)
open! Base

let query conn left right = [%pgsql conn "SELECT id FROM people WHERE $left = $right"]
