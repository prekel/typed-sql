open! Base
open Typed_sql

type row
type other

let table : row Table.t = Table.v_exn "items"
let other : other Table.t = Table.v_exn "other"
let id = Column.v_exn table "id" Db_type.int64
let other_id = Column.v_exn other "id" Db_type.int64

let _ =
  Insert.(
    into table
    |> set id 1L
    |> on_conflict (Conflict_target.column id)
    |> do_update (fun ~existing:_ ~excluded:_ ->
      Conflict_update.(empty |> set other_id 2L))
    |> command)
;;
