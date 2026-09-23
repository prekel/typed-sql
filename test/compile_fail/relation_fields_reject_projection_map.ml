open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int
  let id reference = Expr.column reference id_column
end

let _ =
  Query.(
    from Item.table
    |> select_relation (fun item ->
      Projection.map (Projection.expr (Item.id item)) ~f:Int.to_string))
;;
