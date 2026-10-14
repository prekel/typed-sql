(* expected: is not compatible with type *)
open! Base

let query conn =
  let values = [ Some "wrong" ] in
  [%pgsql conn "SELECT id FROM native_items WHERE id = ANY($values)"]
;;
