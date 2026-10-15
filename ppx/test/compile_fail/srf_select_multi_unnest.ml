(* expected: UNNEST accepts one array outside FROM *)
open! Base

let query conn ids names = [%pgsql conn "SELECT unnest($ids::int[],$names::text[])"]
