(* expected: missing exact PostgreSQL type *)
open! Base

let query conn = [%pgsql conn {|SELECT id FROM legacy|}]
