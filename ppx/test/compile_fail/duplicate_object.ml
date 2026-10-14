(* expected: duplicate object method name *)
open! Base

let query conn = [%pgsql.object conn {|SELECT id, id FROM people|}]
