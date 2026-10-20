open! Base
open Typed_sql

let target : unit Table.t = Table.v_exn "items"
let column = Column.v_exn target "id" Db_type.int
let invalid = Assignment.(column := Expr.constant Db_type.text "wrong")
