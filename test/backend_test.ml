open! Base
open Typed_sql
open Expr.Infix
module B = Typed_sql_backend

let compile_exn dialect query =
  Query.to_result query
  |> Compiler.compile ~dialect
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
;;

let%expect_test "query shape excludes values and generative source ids" =
  let table : unit Table.t = Table.v_exn "people" in
  let name = Column.v_exn table "name" Db_type.text in
  let make value =
    Query.from table ~select:(fun row -> Projection.expr (Expr.column row name))
    |> Query.where (fun row -> Expr.column row name =$ value)
    |> compile_exn Dialect.Postgresql
  in
  let first = make "Ada" in
  let second = make "Grace" in
  Stdlib.print_endline
    (Bool.to_string
       (B.Shape.equal (B.Compiled_query.shape first) (B.Compiled_query.shape second)));
  Stdlib.print_endline (Int.to_string (List.length (B.Compiled_query.parameters first)));
  [%expect
    {|
    true
    1 |}]
;;

let%expect_test "mapped codecs with the same name have distinct shapes" =
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
    Query.from table ~select:(fun row -> Projection.expr (Expr.column row column))
    |> compile_exn Dialect.Sqlite
    |> B.Compiled_query.shape
  in
  Stdlib.print_endline
    (Bool.to_string (B.Shape.equal (make (mapped ())) (make (mapped ()))));
  [%expect {| false |}]
;;
