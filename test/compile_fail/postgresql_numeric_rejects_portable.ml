open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let amount = Column.v_exn table "amount" Db_type.numeric

let query =
  Query.Aggregate.(from table)
  |> Query.aggregate_one (fun row ->
    Postgresql.Numeric_projection.sum_numeric (Expr.column row amount))
;;

let _statement = Statement.Portable.query_one (fun _ -> query)
