open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int64
let name = Column.v_exn table "name" Db_type.text

let _ =
  Insert.(
    into table
    |> values Assignment.[ value id 1L ]
    |> on_conflict (Conflict_target.column id)
    |> do_update (fun ~existing:_ ~excluded ->
      Conflict_update.(empty |> set Assignment.[ expr name (Expr.column excluded id) ]))
    |> command)
;;
