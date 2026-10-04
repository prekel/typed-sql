open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int64

let _ =
  Merge.(
    into table
    |> using table ~f:(fun _ _ merge ->
      merge
      |> on Condition.true_
      |> when_not_matched_insert Assignments.(empty |> set id "not an integer"))
    |> command)
;;
