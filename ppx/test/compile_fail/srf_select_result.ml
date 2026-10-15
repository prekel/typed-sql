(* expected: int64 *)
open! Base

let query conn : int64 option list = [%pgsql conn "SELECT generate_series(1,3)"]
