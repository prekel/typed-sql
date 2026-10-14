(* expected: pgsql.object requires RETURNING *)
open! Base

let query conn = [%pgsql.object conn "DELETE FROM ppx_items"]
