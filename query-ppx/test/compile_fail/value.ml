open! Base

let id = 1

let query =
  [%pgsql.query.object "SELECT id, name FROM typed_sql_query_items WHERE id = $id"]
;;
