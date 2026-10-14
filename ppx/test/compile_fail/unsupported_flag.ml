(* expected: unsupported flag: execute *)
open! Base

let query conn = [%pgsql conn "execute" {|SELECT id FROM people|}]
