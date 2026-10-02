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
    |> Postgresql.Query.for_update ~skip_locked:true
    |> select (fun item -> Projection.expr (Expr.column item Item.id)))
;;

let _ = Statement.query_many ~dialect:Dialect.portable query
