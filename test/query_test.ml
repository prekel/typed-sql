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
  let nickname_column = Column.nullable_v_exn table "nickname" Db_type.text
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

module Department = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "departments"
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let person_id reference = Expr.column reference person_id_column
  let name reference = Expr.column reference name_column
  let nullable_name reference = Expr.nullable_column reference name_column
end

let compile_exn dialect query =
  match Compiler.compile ~dialect (Query.to_result query) with
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
  (match Compiler.compile ~dialect:Dialect.Sqlite (Query.to_result query) with
   | Ok _ -> Stdlib.print_endline "unexpected success"
   | Error (Compile_error.Foreign_source _) -> Stdlib.print_endline "foreign source"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  [%expect {| foreign source |}]
;;

let%expect_test "invalid limits and empty projections are validation errors" =
  let empty = Query.from Person.table ~select:(fun _ -> Projection.pure ()) in
  let negative = Query.from Person.table ~select:Person.projection |> Query.limit (-1) in
  (match Compiler.compile ~dialect:Dialect.Sqlite (Query.to_result empty) with
   | Ok _ -> Stdlib.print_endline "unexpected success"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  (match Compiler.compile ~dialect:Dialect.Sqlite (Query.to_result negative) with
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

let%expect_test "joins use deterministic aliases and LEFT JOIN makes its side nullable" =
  let inner =
    Query.from Person.table ~select:(fun person -> Projection.expr (Person.id person))
    |> Query.inner_join Department.table ~on:(fun person department ->
      Expr.eq (Person.id person) (Department.person_id department))
    |> Query.select (fun (person, department) ->
      Projection.map2
        (fun person_id department_name -> person_id, department_name)
        (Projection.expr (Person.id person))
        (Projection.expr (Department.name department)))
  in
  let left =
    Query.from Person.table ~select:(fun person -> Projection.expr (Person.id person))
    |> Query.left_join Department.table ~on:(fun person department ->
      Expr.eq (Person.id person) (Department.person_id department))
    |> Query.select (fun (person, department) ->
      Projection.map2
        (fun person_id department_name -> person_id, department_name)
        (Projection.expr (Person.id person))
        (Projection.expr (Department.nullable_name department)))
  in
  inner |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  left |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {|
    SELECT t0."id", t1."name" FROM "public"."people" AS t0 INNER JOIN "public"."departments" AS t1 ON (t0."id" = t1."person_id")
    SELECT t0."id", t1."name" FROM "public"."people" AS t0 LEFT JOIN "public"."departments" AS t1 ON (t0."id" = t1."person_id") |}]
;;

let compile_result_exn dialect query =
  match Compiler.compile ~dialect query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let compile_command_exn dialect command =
  match Compiler.compile_command ~dialect command with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let%expect_test "portable DML and RETURNING" =
  Insert.into Person.table
  |> Insert.set Person.id_column 42L
  |> Insert.set Person.name_column "Ada"
  |> Insert.returning (fun person -> Projection.expr (Person.id person))
  |> compile_result_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  Update.table Person.table
  |> Update.set Person.name_column "Grace"
  |> Update.where (fun person -> Expr.eq_value (Person.id person) 42L)
  |> Update.command
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  Delete.from Person.table
  |> Delete.all_rows
  |> Delete.command
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" ("id", "name") VALUES ($1, $2) RETURNING "id"
    UPDATE "public"."people" SET "name" = ?1 WHERE ("id" = ?2)
    DELETE FROM "public"."people" |}]
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
    |> Compiled_query.shape
  in
  Stdlib.print_endline
    (Bool.to_string (Shape.equal (make (mapped ())) (make (mapped ()))));
  [%expect {| false |}]
;;
