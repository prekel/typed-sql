open! Base
open Typed_sql

type row

let t : row Table.t = Table.v_exn "items"
let c = Column.v_exn t "rating" Db_type.int

let scalar =
  Query.(
    from t
    |> select_scalar (fun _ -> Postgresql.Numeric.avg_int (Expr.constant Db_type.int 1)))
;;

let update =
  Update.(
    table t
    |> set_nullable_expr
         c
         (Expr.cast_float_to_int_nullable
            (Expr.cast_int_to_float_nullable
               (Postgresql.Numeric.cast_numeric_to_int_nullable
                  (Expr.scalar_subquery_nullable scalar))))
    |> all_rows
    |> command)
;;

let invalid = Statement.command ~dialect:Dialect.portable update
