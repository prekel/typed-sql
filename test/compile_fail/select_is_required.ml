open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let _ = Statement.query_many ~dialect:Dialect.sqlite Query.(from table)
