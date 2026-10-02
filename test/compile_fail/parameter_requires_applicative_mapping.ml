open! Base
open Typed_sql
open Infix

type row

let table : row Table.t = Table.v_exn "items"
let id_column = Column.v_exn table "id" Db_type.int

let _statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let id = params.expr Db_type.int ~get:Fn.id in
    Statement.Parameters.return
      (params.query_many
         Query.(
           from table
           |> where (fun row -> Expr.column row id_column =. id)
           |> select (fun row -> Projection.expr (Expr.column row id_column)))))
;;
