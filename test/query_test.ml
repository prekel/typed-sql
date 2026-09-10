open! Base
open Typed_sql

module Person = struct
  type row

  type t =
    { id : int64
    ; name : string
    ; nickname : string option
    }

  let table : row Table.t = Table.v_exn ~schema:"public" "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let nickname_column = Column.v_exn table "nickname" (Db_type.option Db_type.text)
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column
  let nickname reference = Expr.column reference nickname_column

  let projection reference =
    Projection.map3
      (fun id name nickname -> { id; name; nickname })
      (Projection.expr (id reference))
      (Projection.expr (name reference))
      (Projection.expr (nickname reference))
  ;;
end

let compile_exn dialect query =
  match Compiler.compile ~dialect query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let%expect_test "PostgreSQL and SQLite rendering" =
  let query =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person ->
      Condition.all
        [ Condition.true_
        ; Expr.eq_value (Person.name person) "Ada"
        ; Expr.gt_value Db_type.Ordering.int64 (Person.id person) 10L
        ])
    |> Query.order_by (fun person -> Person.id person) `Desc
    |> Query.limit 20
    |> Query.offset 5
  in
  let postgres = compile_exn Dialect.Postgresql query in
  let sqlite = compile_exn Dialect.Sqlite query in
  Stdlib.print_endline (Compiled_query.sql postgres);
  Stdlib.print_endline (Compiled_query.sql sqlite);
  [%expect
    {|
    SELECT t0."id", t0."name", t0."nickname" FROM "public"."people" AS t0 WHERE ((t0."name" = $1) AND (t0."id" > $2)) ORDER BY t0."id" DESC LIMIT 20 OFFSET 5
    SELECT t0."id", t0."name", t0."nickname" FROM "public"."people" AS t0 WHERE ((t0."name" = ?1) AND (t0."id" > ?2)) ORDER BY t0."id" DESC LIMIT 20 OFFSET 5 |}]
;;

let%expect_test "query shape excludes values and generative source ids" =
  let make value =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person -> Expr.eq_value (Person.name person) value)
    |> compile_exn Dialect.Postgresql
  in
  let first = make "Ada" in
  let second = make "Grace" in
  Stdlib.print_endline
    (Bool.to_string
       (Shape.equal (Compiled_query.shape first) (Compiled_query.shape second)));
  Stdlib.print_endline (Int.to_string (List.length (Compiled_query.parameters first)));
  [%expect
    {|
    true
    1 |}]
;;

let%expect_test "escaped table reference is rejected" =
  let escaped = ref None in
  let _ =
    Query.from Person.table ~select:(fun person ->
      escaped := Some person;
      Person.projection person)
  in
  let foreign = Option.value_exn !escaped in
  let query =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun _ -> Expr.eq_value (Person.name foreign) "Ada")
  in
  (match Compiler.compile ~dialect:Dialect.Sqlite query with
   | Ok _ -> Stdlib.print_endline "unexpected success"
   | Error (Compile_error.Foreign_source _) -> Stdlib.print_endline "foreign source"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  [%expect {| foreign source |}]
;;

let%expect_test "invalid limits and empty projections are validation errors" =
  let empty = Query.from Person.table ~select:(fun _ -> Projection.pure ()) in
  let negative = Query.from Person.table ~select:Person.projection |> Query.limit (-1) in
  (match Compiler.compile ~dialect:Dialect.Sqlite empty with
   | Ok _ -> Stdlib.print_endline "unexpected success"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  (match Compiler.compile ~dialect:Dialect.Sqlite negative with
   | Ok _ -> Stdlib.print_endline "unexpected success"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  [%expect
    {|
    SELECT projection must contain at least one expression
    LIMIT must be non-negative, got -1 |}]
;;

let%expect_test "identifiers are always quoted" =
  let table : unit Table.t = Table.v_exn "select" in
  let column = Column.v_exn table "quoted\"name" Db_type.text in
  let query =
    Query.from table ~select:(fun reference ->
      Projection.expr (Expr.column reference column))
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect {| SELECT t0."quoted""name" FROM "select" AS t0 |}]
;;
