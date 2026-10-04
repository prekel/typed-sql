open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let title = Column.v_exn table "title" Db_type.text

let _ =
  Merge.(
    into table
    |> using table ~f:(fun _ _ merge ->
      merge
      |> on Condition.true_
      |> when_not_matched_insert
           Assignments.(
             empty |> set_expr title (Expr.constant (Db_type.option Db_type.text) None)))
    |> command)
;;
