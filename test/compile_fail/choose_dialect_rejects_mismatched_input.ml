open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
end

let query = Query.(from Item.table |> select (fun _ -> Projection.expr Expr.count_all))

let postgresql =
  Statement.For_dialect.query_many_exn
    ~dialect:Dialect.postgresql
    (fun (_ : (unit, Dialect.postgresql) Statement.parameters) -> query)
;;

let sqlite =
  Statement.For_dialect.query_many_exn
    ~dialect:Dialect.sqlite
    (fun (_ : (int, Dialect.sqlite) Statement.parameters) -> query)
;;

let _ = Statement.choose_dialect ~postgresql ~sqlite
