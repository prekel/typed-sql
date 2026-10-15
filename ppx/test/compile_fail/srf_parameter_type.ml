(* expected: int64 *)
open! Base

let query conn (stop : int64) = [%pgsql conn "SELECT * FROM generate_series(1,$stop)"]
