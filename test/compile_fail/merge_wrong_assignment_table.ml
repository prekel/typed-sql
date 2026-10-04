open! Base
open Typed_sql

type row
type other

let table : row Table.t = Table.v_exn "items"
let other : other Table.t = Table.v_exn "other_items"
let other_id = Column.v_exn other "id" Db_type.int64

let _ =
  Merge.(
    into table
    |> using other ~f:(fun _ _ merge ->
      merge
      |> on Condition.true_
      |> when_matched_update Assignments.(empty |> set other_id 1L))
    |> command)
;;
