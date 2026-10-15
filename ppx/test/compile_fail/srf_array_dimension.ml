(* expected: int32 *)
open! Base

let query conn (dimension : int64) =
  [%pgsql conn "SELECT array_length(numbers,$dimension) FROM native_items"]
;;
