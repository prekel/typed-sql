open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int64

let _ =
  Merge.(
    into table |> returning (fun target _ -> Projection.expr (Expr.column target id)))
;;
