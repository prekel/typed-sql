open! Base
open Typed_sql

type item
type account

let items : item Table.t = Table.v_exn "items"
let accounts : account Table.t = Table.v_exn "accounts"
let item_id = Column.v_exn items "id" Db_type.int64
let account_id = Column.v_exn accounts "id" Db_type.int64

let _ =
  Insert.(
    into items
    |> set item_id 1L
    |> on_conflict (Conflict_target.column account_id)
    |> do_nothing
    |> command)
;;
