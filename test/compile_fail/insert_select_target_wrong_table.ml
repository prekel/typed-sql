open! Base
open Typed_sql

type target
type other

let targets : target Table.t = Table.v_exn "targets"
let others : other Table.t = Table.v_exn "others"
let other_id = Column.v_exn others "id" Db_type.int64

let source =
  Query.(from others |> select (fun row -> Projection.expr (Expr.column row other_id)))
;;

let _ = Insert.(into targets |> from_select (Columns.column other_id) source |> command)
