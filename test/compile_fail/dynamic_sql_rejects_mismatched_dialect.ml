open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
end

let statement =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
    Query.(from Item.table |> select (fun _ -> Projection.expr Expr.count_all)))
;;

let _ = Statement.sql ~dialect:Sqlite ~input:() statement
