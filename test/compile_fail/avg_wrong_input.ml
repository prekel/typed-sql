open! Base
open Typed_sql

let invalid = Expr.avg_int (Expr.constant Db_type.float 1.)
