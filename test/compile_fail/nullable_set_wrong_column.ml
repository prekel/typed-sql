open! Base
open Typed_sql

type a
type b

let target : a Table.t = Table.v_exn "a"
let other : b Table.t = Table.v_exn "b"
let column = Column.v_exn other "value" Db_type.int

let invalid =
  Update.(
    table target
    |> set_nullable_expr column (Expr.constant (Db_type.option Db_type.int) None)
    |> all_rows
    |> command)
;;
