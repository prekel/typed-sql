open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let id_column = Column.v_exn table "id" Db_type.int64

let query =
  Query.(
    from table
    |> where (fun row ->
      Postgresql.Expr.equals_any_list
        (Expr.column row id_column)
        (Expr.constant (Db_type.Postgresql.array_list Db_type.int64) [ 1L ]))
    |> select (fun row -> Projection.expr (Expr.column row id_column)))
;;

let _statement = Statement.query_many ~dialect:Dialect.portable query
