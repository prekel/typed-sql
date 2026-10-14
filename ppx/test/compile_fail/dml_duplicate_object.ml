(* expected: duplicate object method name: id *)
open! Base

let query conn = [%pgsql.object conn "DELETE FROM ppx_items RETURNING id, id"]
