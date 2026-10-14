(* expected: conflict columns do not match a primary or unique key *)
open! Base

let query conn id =
  [%pgsql conn "INSERT INTO ppx_items (id) VALUES ($id) ON CONFLICT (id) DO NOTHING"]
;;
