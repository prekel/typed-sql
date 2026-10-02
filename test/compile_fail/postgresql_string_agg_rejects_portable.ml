open! Base
open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let value_column = Column.v_exn table "value" Db_type.text

let query =
  Query.(
    from table
    |> select_exactly_one (fun row ->
      Projection.expr
        (Postgresql.string_agg
           ~delimiter:(Expr.constant Db_type.text ",")
           (Expr.column row value_column))))
;;

let _statement = Statement.query_one ~dialect:Dialect.portable query
