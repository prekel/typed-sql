(* expected: unknown column: missing *)
open! Base

let query conn = [%pgsql conn "UPDATE ppx_items SET missing = DEFAULT"]
