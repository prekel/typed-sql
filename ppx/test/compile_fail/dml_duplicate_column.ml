(* expected: duplicate target column: id *)
open! Base

let query conn id = [%pgsql conn "INSERT INTO ppx_items (id, id) VALUES ($id, $id)"]
