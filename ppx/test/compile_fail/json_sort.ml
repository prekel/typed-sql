(* expected: PostgreSQL json has no ordering operator *)
open! Base

let query conn = [%pgsql conn {|SELECT document FROM people ORDER BY document|}]
