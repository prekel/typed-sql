open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let rating = Column.v_exn table "rating" Db_type.int

let invalid =
  Update.(
    table table
    |> set_expr
         rating
         (Expr.cast_float_to_int_nullable (Expr.avg_int (Expr.constant Db_type.int 1)))
    |> all_rows
    |> command)
;;
