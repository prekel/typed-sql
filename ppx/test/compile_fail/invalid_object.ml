(* expected: invalid object method name *)
open! Base

let query conn = [%pgsql.object conn {|SELECT name AS "Upper" FROM people|}]
