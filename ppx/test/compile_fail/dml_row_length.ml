(* expected: VALUES row length does not match INSERT columns *)
open! Base

let query conn id = [%pgsql conn "INSERT INTO ppx_items (id, name) VALUES ($id)"]
