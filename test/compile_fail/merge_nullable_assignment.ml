open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let title = Column.nullable_v_exn table "title" Db_type.text

let _ =
  Merge.(
    into table
    |> using table ~f:(fun _ _ merge ->
      merge
      |> on Condition.true_
      |> when_matched_update
           Assignments.(
             empty |> set_expr title (Expr.constant Db_type.text "not nullable")))
    |> command)
;;
