open! Base
open Typed_sql
open Infix
module B = Typed_sql_backend

let compile_exn dialect query =
  Compiler.compile ~dialect query
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
;;

let%test_unit "query shape excludes values and generative source ids" =
  let table : unit Table.t = Table.v_exn "people" in
  let name = Column.v_exn table "name" Db_type.text in
  let make value =
    Query.(
      from table
      |> where (fun row -> Expr.column row name =$ value)
      |> select (fun row -> Projection.expr (Expr.column row name)))
    |> compile_exn Dialect.Postgresql
  in
  let first = make "Ada" in
  let second = make "Grace" in
  assert (B.Shape.equal (B.Compiled_query.shape first) (B.Compiled_query.shape second));
  assert (Int.equal (List.length (B.Compiled_query.parameters first)) 1)
;;

let%test "mapped codecs with the same name have distinct shapes" =
  let mapped () =
    Db_type.map
      ~name:"id"
      ~encode:(fun value -> Ok value)
      ~decode:(fun value -> Ok value)
      Db_type.int64
  in
  let make db_type =
    let table : unit Table.t = Table.v_exn "ids" in
    let column = Column.v_exn table "id" db_type in
    Query.(from table |> select (fun row -> Projection.expr (Expr.column row column)))
    |> compile_exn Dialect.Sqlite
    |> B.Compiled_query.shape
  in
  not (B.Shape.equal (make (mapped ())) (make (mapped ())))
;;
