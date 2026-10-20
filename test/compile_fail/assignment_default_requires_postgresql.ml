open! Base
open Typed_sql

let target : unit Table.t = Table.v_exn "items"
let column = Column.v_exn target "id" Db_type.int

let invalid =
  Statement.command
    ~dialect:Dialect.portable
    Insert.(into target |> values Assignment.[ default column ] |> command)
;;
