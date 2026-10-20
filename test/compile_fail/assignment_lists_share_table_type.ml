open! Base
open Typed_sql

type first
type second

let first : first Table.t = Table.v_exn "first"
let second : second Table.t = Table.v_exn "second"
let first_id = Column.v_exn first "id" Db_type.int
let second_id = Column.v_exn second "id" Db_type.int
let invalid = Assignment.[ value first_id 1; value second_id 2 ]
