(* expected: unsupported trailing SQL *)
open! Base

let query conn name =
  [%pgsql conn "UPDATE ppx_items SET name = $name FROM ppx_items other"]
;;
