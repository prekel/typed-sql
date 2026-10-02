open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id = Column.v_exn table "id" Db_type.int64
  let name = Column.v_exn table "name" Db_type.text
end

let postgresql =
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(
      from Item.table |> select (fun item -> Projection.expr (Expr.column item Item.id)))
;;

let sqlite =
  Statement.query_many
    ~dialect:Dialect.sqlite
    Query.(
      from Item.table |> select (fun item -> Projection.expr (Expr.column item Item.name)))
;;

let _ = Statement.choose_dialect ~postgresql ~sqlite
