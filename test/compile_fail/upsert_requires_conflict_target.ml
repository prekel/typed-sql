open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"

let _ =
  Insert.(
    into table
    |> do_update (fun ~existing:_ ~excluded:_ -> Conflict_update.empty)
    |> command)
;;
