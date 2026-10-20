open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int64

let _ =
  Insert.(
    into table
    |> values Assignment.[ value id 1L ]
    |> on_conflict (Conflict_target.column id)
    |> command)
;;
