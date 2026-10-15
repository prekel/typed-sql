(* expected: unknown column: missing *)
open! Base

let query conn name =
  [%pgsql
    conn "UPDATE ppx_items SET name = $name FROM ppx_items other WHERE other.missing = 1"]
;;
