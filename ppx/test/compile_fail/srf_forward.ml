(* expected: column qualifier does not name the statement source *)
open! Base

let query conn = [%pgsql conn "SELECT u FROM unnest(n.numbers) u,native_items n"]
