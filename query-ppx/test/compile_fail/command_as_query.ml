open! Base

let id = Typed_sql.Expr.constant Typed_sql.Db_type.int 1
let query = [%pgsql.query "DELETE FROM typed_sql_query_items WHERE id = $id"]
