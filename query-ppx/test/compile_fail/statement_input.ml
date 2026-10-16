open! Base

let statement =
  [%pgsql.statement fun id -> "DELETE FROM typed_sql_query_items WHERE id = $id"]
;;

let sql = Typed_sql.Statement.sql_exn ~dialect:Postgresql ~input:() statement
