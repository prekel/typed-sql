(* expected: unknown column: missing *)
open! Base

let query conn = [%pgsql conn {|SELECT missing FROM people|}]
