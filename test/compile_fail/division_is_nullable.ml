open! Base
open Typed_sql

let result : (int, Dialect.portable) Expr.t =
  Expr.Int.Infix.(Expr.constant Db_type.int 1 /. Expr.constant Db_type.int 0)
;;
