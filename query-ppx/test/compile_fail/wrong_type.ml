open! Base

let id = Typed_sql.Expr.constant Typed_sql.Db_type.int64 1L

let query =
  [%pgsql.query.object "SELECT id, name FROM typed_sql_query_items WHERE id = $id"]
;;
