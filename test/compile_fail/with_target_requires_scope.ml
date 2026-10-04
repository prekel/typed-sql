open! Base
open Typed_sql

type row

let target : row Table.t = Table.v_exn "items"
let column = Column.v_exn target "rating" Db_type.int

let invalid =
  Update.(
    table target |> with_target ~f:(fun _ update -> update |> set column 1) |> command)
;;
