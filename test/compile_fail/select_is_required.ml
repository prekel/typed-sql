open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"

let _ =
  Statement.For_dialect.query_many ~dialect:Dialect.sqlite (fun _ -> Query.(from table))
;;
