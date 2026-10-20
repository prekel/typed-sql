open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"
let column = Column.nullable_v_exn table "id" Db_type.int
let invalid = Assignment.value column 1
