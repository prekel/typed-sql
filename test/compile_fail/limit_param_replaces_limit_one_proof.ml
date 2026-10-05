open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int

let _ =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    Parameters.map (params.non_negative_int ~name:"maximum" ~get:Fn.id) ~f:(fun maximum ->
      params.query_optional
        Query.(
          from table
          |> limit_one
          |> limit_param maximum
          |> select (fun item -> Projection.expr (Expr.column item id)))))
;;
