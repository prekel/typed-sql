open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id = Column.v_exn table "id" Db_type.int
end

let query =
  Query.(
    from Item.table
    |> limit_one
    |> order_by (fun item -> Expr.column item Item.id) `Asc
    |> Postgresql.Query.fetch_with_ties 1
    |> select (fun item -> Projection.expr (Expr.column item Item.id)))
;;

let _ = Statement.For_dialect.query_optional ~dialect:Dialect.postgresql (fun _ -> query)
