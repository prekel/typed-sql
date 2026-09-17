open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int

let statement =
  Statement.Dynamic.Portable.command (fun () ->
    Insert.(into table |> default id |> command))
;;
