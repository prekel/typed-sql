open! Base
open Typed_sql
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int64
end

let _ =
  Query.(
    from Item.table
    |> left_join Item.table ~on:(fun left right ->
      Expr.column left Item.id_column =. Expr.column right Item.id_column)
    |> select (fun (_, right) -> Projection.expr (Expr.column right Item.id_column)))
;;
