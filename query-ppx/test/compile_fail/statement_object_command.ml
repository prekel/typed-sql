open! Base

let statement =
  [%pgsql.statement.object fun id -> "DELETE FROM typed_sql_query_items WHERE id = $id"]
;;
