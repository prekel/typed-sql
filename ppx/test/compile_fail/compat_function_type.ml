(* expected: unsupported PostgreSQL function overload *)
open! Base

let query conn = [%pgsql conn "SELECT lower(id) FROM join_people"]
