(* expected: expected of type int32 *)
open! Base

let query conn =
  let id = "wrong" in
  [%pgsql conn "INSERT INTO ppx_items (id) VALUES ($id)"]
;;
