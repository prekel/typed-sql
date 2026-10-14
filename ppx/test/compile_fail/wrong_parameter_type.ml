(* expected: int32 *)
open! Base

let query conn =
  let id = "wrong" in
  [%pgsql conn {|SELECT id FROM people WHERE id = $id|}]
;;
