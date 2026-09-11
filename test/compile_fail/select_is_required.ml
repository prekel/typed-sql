open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let _ = Query.(from table) |> Compiler.compile ~dialect:Dialect.Sqlite
