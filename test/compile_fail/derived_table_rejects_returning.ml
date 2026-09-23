open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int
  let id reference = Expr.column reference id_column
end

module Returned_item = struct
  type row

  let table : row Table.t = Table.v_exn "returned_items"
  let id_column = Column.v_exn table "id" Db_type.int
  let id reference = Expr.column reference id_column
end

let returned =
  Insert.(
    into Item.table
    |> set Item.id_column 1
    |> returning (fun item -> Projection.expr (Item.id item)))
;;

let _ =
  Derived_table.create
    ~table:Returned_item.table
    ~columns:(fun item -> Projection.expr (Returned_item.id item))
    returned
;;
