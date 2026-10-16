open! Base

let statement =
  [%pgsql.statement
    fun id -> "nullable-results" "DELETE FROM typed_sql_query_items WHERE id = $id"]
;;
