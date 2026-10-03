open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
end

let query = Query.(from Item.table |> select (fun _ -> Projection.expr Expr.count_all))
let statement = Statement.query_many ~dialect:Dialect.sqlite query
let _ = Statement.sql ~dialect:postgresql statement
