open! Base

let statement = [%pgsql.statement "SELECT 1::int4 AS id"]
let sql = Typed_sql.Statement.sql_exn ~dialect:Sqlite statement
