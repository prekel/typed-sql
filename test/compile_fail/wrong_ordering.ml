open! Base
open Typed_sql
open Expr.Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
end

let _ =
  Query.from Item.table ~select:(fun item ->
    Projection.expr (Expr.column item Item.name_column))
  |> Query.where (fun item ->
    Expr.column item Item.name_column >. Expr.column item Item.id_column)
;;
