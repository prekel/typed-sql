(* expected: incompatible PostgreSQL operand types *)
open! Base

let query conn = [%pgsql conn "SELECT id FROM people WHERE id = name"]
