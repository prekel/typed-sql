(* expected: expected = *)
open! Base

let query conn id = [%pgsql conn "UPDATE ppx_items AS i SET i.id = $id"]
