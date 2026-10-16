open! Base

let id = 1
let statement = [%pgsql.statement "DELETE FROM typed_sql_query_items WHERE id = $id"]
