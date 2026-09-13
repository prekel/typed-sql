open Typed_sql
open Infix

module Resource = struct
  type row

  let table : row Table.t = Table.v_exn "resources"
  let external_id_column = Column.v_exn table "external_id" Db_type.uuid
end

let query =
  Query.(
    from Resource.table
    |> where (fun resource -> Expr.column resource Resource.external_id_column =$ "text")
    |> select (fun resource ->
      Projection.expr (Expr.column resource Resource.external_id_column)))
;;
