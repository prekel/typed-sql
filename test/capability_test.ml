open! Base
open Typed_sql
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id = Column.v_exn table "id" Db_type.int
end

let portable_query =
  Query.(
    from Item.table
    |> where (fun item -> Expr.column item Item.id >$ 0)
    |> select (fun item -> Projection.expr (Expr.column item Item.id)))
;;

let compiled_for_postgresql = Compiler.compile ~dialect:Dialect.postgresql portable_query
let compiled_for_sqlite = Compiler.compile ~dialect:Dialect.sqlite portable_query

let%test "a portable query accepts both static dialect witnesses" =
  match compiled_for_postgresql, compiled_for_sqlite with
  | Ok _, Ok _ -> true
  | Error _, _ | _, Error _ -> false
;;
