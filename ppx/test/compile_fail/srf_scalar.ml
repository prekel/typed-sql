(* expected: set-returning functions are not allowed in this clause *)
open! Base

let query conn = [%pgsql conn "SELECT id FROM native_items WHERE unnest(numbers) = id"]
