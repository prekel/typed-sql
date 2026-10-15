(* expected: int32 *)
open! Base

let query conn (buckets : string) =
  [%pgsql conn "SELECT ntile($buckets) OVER() FROM join_people"]
;;
