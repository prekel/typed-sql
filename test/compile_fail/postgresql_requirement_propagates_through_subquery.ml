open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
end

let scalar =
  Query.(
    from Item.table
    |> Postgresql.Query.having (fun _ -> Condition.true_)
    |> limit 1
    |> select_scalar (fun _ -> Expr.count_all))
  |> Expr.scalar_subquery
;;

let query = Query.(from Item.table |> select (fun _ -> Projection.expr scalar))
let _ = Statement.query_many ~dialect:Dialect.sqlite query
