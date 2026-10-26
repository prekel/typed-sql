open! Base

let query conn = [%pgsql conn "SELECT id FROM people"]

let insert conn tenant id name : unit =
  [%pgsql conn "INSERT INTO ppx_items (tenant, id, name) VALUES ($tenant, $id, $name)"]
;;

let save conn tenant id name : int32 list =
  [%pgsql
    conn
      "INSERT INTO ppx_items (tenant, id, name) VALUES ($tenant, $id, $name) ON CONFLICT (tenant, id) DO UPDATE SET name = EXCLUDED.name RETURNING id"]
;;

let update conn id note : string option list =
  [%pgsql conn "UPDATE ppx_items SET note = $?note WHERE id = $id RETURNING note"]
;;

let delete conn id : unit = [%pgsql conn "DELETE FROM ppx_items WHERE id = $id"]
