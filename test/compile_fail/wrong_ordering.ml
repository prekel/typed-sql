open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let name_column = Column.v_exn table "name" Db_type.text
end

let _ =
  Query.from Item.table ~select:(fun item ->
    Projection.expr (Expr.column item Item.name_column))
  |> Query.where (fun item ->
    Expr.gt_value Db_type.Ordering.int64 (Expr.column item Item.name_column) "threshold")
;;
