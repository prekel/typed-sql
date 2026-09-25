open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let value = Column.v_exn table "value" Db_type.int

let _query =
  Query.Aggregate.(from table)
  |> Query.aggregate_one (fun row -> Projection.expr (Expr.column row value))
;;
