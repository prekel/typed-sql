open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int

let query =
  Query.(from table |> select (fun item -> Projection.expr (Expr.column item id)))
;;

let _ = Statement.query_optional ~dialect:Dialect.portable query
