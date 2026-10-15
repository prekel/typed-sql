(* expected: window functions are not allowed *)
open! Base

let query conn = [%pgsql conn "SELECT id FROM join_people WHERE row_number() OVER()>1"]
