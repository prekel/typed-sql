open! Base
open Typed_sql

let invalid = Expr.cast_int_to_float_nullable (Expr.constant Db_type.int 1)
