(* expected: EXCLUDED assignment requires identical native types *)
open! Base

let query conn id =
  [%pgsql
    conn
      "INSERT INTO ppx_items (id) VALUES ($id) ON CONFLICT (tenant, id) DO UPDATE SET name = EXCLUDED.id"]
;;
