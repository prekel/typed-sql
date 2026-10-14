(* expected: unsupported PostgreSQL type *)
open! Base

let query conn = [%pgsql conn {|SELECT numbers FROM unsupported|}]
