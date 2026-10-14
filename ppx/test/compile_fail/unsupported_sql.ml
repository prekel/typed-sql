(* expected: unsupported trailing SQL *)
open! Base

let query conn = [%pgsql conn {|SELECT id FROM people JOIN people p ON true|}]
