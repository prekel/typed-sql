open! Base

let statement =
  Typed_sql.Statement.query_many
    ~dialect:Typed_sql.Dialect.sqlite
    [%pgsql.query "SELECT 1::int4 AS id"]
;;
