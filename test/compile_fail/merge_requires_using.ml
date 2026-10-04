open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let _ = Merge.(into table |> command)
