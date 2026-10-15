(* expected: int32 *)
open! Base

let query conn : (int32 option * int32 option) list =
  [%pgsql conn "SELECT * FROM generate_series(1,3) WITH ORDINALITY"]
;;
