(* expected: UNNEST requires a known array type *)
open! Base

let query conn = [%pgsql conn "SELECT * FROM unnest(1)"]
