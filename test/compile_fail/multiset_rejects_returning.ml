open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int
  let id reference = Expr.column reference id_column
end

let returned =
  Insert.(
    into Item.table
    |> set Item.id_column 1
    |> returning (fun item -> Projection.expr (Item.id item)))
;;

let _ = Query.multiset returned
