open! Base
open Typed_sql
open Infix

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
      ~f:(fun id name nickname -> { id; name; nickname })
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
  match Compiler.compile ~dialect query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let%expect_test "PostgreSQL and SQLite rendering" =
  let query =
    Query.(
      from Person.table
      |> where (fun person ->
        Condition.true_ &&. (Person.name person =$ "Ada") &&. (Person.id person >$ 10L))
      |> order_by (fun person -> Person.id person) `Desc
      |> limit 20
      |> offset 5
      |> select (fun person -> Projection.pair (Person.id person) (Person.name person)))
  in
  let postgres = compile_exn Dialect.Postgresql query in
  let sqlite = compile_exn Dialect.Sqlite query in
  Stdlib.print_endline (Compiled_query.sql postgres);
  [%expect
    {| SELECT t0."id", t0."name" FROM "public"."people" AS t0 WHERE ((t0."name" = $1) AND (t0."id" > $2)) ORDER BY t0."id" DESC LIMIT 20 OFFSET 5 |}];
  Stdlib.print_endline (Compiled_query.sql sqlite);
  [%expect
    {| SELECT t0."id", t0."name" FROM "public"."people" AS t0 WHERE ((t0."name" = ?1) AND (t0."id" > ?2)) ORDER BY t0."id" DESC LIMIT 20 OFFSET 5 |}]
;;

let%expect_test "infix comparison operators render in source order" =
  let query =
    Query.(
      from Person.table
      |> where (fun person ->
        Person.id person
        <$ 1L
        &&. (Person.id person <=$ 2L)
        &&. (Person.id person >$ 3L)
        &&. (Person.id person >=$ 4L)
        &&. (Person.id person <>$ 5L)
        &&. (Person.name person =~$ "A%"))
      |> select Person.projection)
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."id", t0."name", t0."nickname" FROM "public"."people" AS t0 WHERE ((t0."id" < $1) AND (t0."id" <= $2) AND (t0."id" > $3) AND (t0."id" >= $4) AND (t0."id" <> $5) AND (t0."name" LIKE $6)) |}]
;;

let%test "escaped table reference is rejected" =
  let escaped = ref None in
  let _ =
    Query.(
      from Person.table
      |> select (fun person ->
        escaped := Some person;
        Person.projection person))
  in
  let foreign = Option.value_exn !escaped in
  let query =
    Query.(
      from Person.table
      |> where (fun _ -> Person.name foreign =$ "Ada")
      |> select Person.projection)
  in
  match Compiler.compile ~dialect:Dialect.Sqlite query with
  | Error (Compile_error.Foreign_source _) -> true
  | _ -> false
;;

let%expect_test "invalid limits and empty projections are validation errors" =
  let empty = Query.(from Person.table |> select (fun _ -> Projection.return ())) in
  let negative = Query.(from Person.table |> limit (-1) |> select Person.projection) in
  (match Compiler.compile ~dialect:Dialect.Sqlite empty with
   | Ok _ -> failwith "unexpected success"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  [%expect {| SELECT projection must contain at least one expression |}];
  (match Compiler.compile ~dialect:Dialect.Sqlite negative with
   | Ok _ -> failwith "unexpected success"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  [%expect {| LIMIT must be non-negative, got -1 |}]
;;

let%expect_test "identifiers are always quoted" =
  let table : unit Table.t = Table.v_exn "select" in
  let column = Column.v_exn table "quoted\"name" Db_type.text in
  let query =
    Query.(
      from table
      |> select (fun reference -> Projection.expr (Expr.column reference column)))
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect {| SELECT t0."quoted""name" FROM "select" AS t0 |}]
;;

let%expect_test "joins use deterministic aliases and LEFT JOIN makes its side nullable" =
  let inner =
    Query.(
      from Person.table
      |> inner_join Department.table ~on:(fun person department ->
        Person.id person =. Department.person_id department)
      |> select (fun (person, department) ->
        Projection.map2
          ~f:(fun person_id department_name -> person_id, department_name)
          (Projection.expr (Person.id person))
          (Projection.expr (Department.name department))))
  in
  let left =
    Query.(
      from Person.table
      |> left_join Department.table ~on:(fun person department ->
        Person.id person =. Department.person_id department)
      |> select (fun (person, department) ->
        Projection.map2
          ~f:(fun person_id department_name -> person_id, department_name)
          (Projection.expr (Person.id person))
          (Projection.expr (Department.nullable_name department))))
  in
  inner |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."id", t1."name" FROM "public"."people" AS t0 INNER JOIN "public"."departments" AS t1 ON (t0."id" = t1."person_id") |}];
  left |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."id", t1."name" FROM "public"."people" AS t0 LEFT JOIN "public"."departments" AS t1 ON (t0."id" = t1."person_id") |}]
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
  Insert.(
    into Person.table
    |> set Person.id_column 42L
    |> set Person.name_column "Ada"
    |> returning (fun person -> Projection.expr (Person.id person)))
  |> compile_result_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {| INSERT INTO "public"."people" ("id", "name") VALUES ($1, $2) RETURNING "id" |}];
  Update.(
    table Person.table
    |> set Person.name_column "Grace"
    |> where (fun person -> Person.id person =$ 42L)
    |> command)
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| UPDATE "public"."people" SET "name" = ?1 WHERE ("id" = ?2) |}];
  Delete.(from Person.table |> all_rows |> command)
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| DELETE FROM "public"."people" |}]
;;

let%expect_test "multi-row INSERT, DEFAULT, conflict policy, and UPDATE FROM" =
  let multi_row =
    Insert.(
      rows
        Person.table
        [ (fun row -> row |> set Person.id_column 1L |> set Person.name_column "Ada")
        ; (fun row -> row |> set Person.name_column "Grace" |> set Person.id_column 2L)
        ]
      |> command)
  in
  multi_row
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| INSERT INTO "public"."people" ("id", "name") VALUES ($1, $2), ($3, $4) |}];
  multi_row
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| INSERT INTO "public"."people" ("id", "name") VALUES (?1, ?2), (?3, ?4) |}];
  Insert.(
    into Person.table
    |> default Person.id_column
    |> set Person.name_column "Ada"
    |> command)
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| INSERT INTO "public"."people" ("id", "name") VALUES (DEFAULT, $1) |}];
  Insert.(
    into Person.table
    |> set Person.id_column 1L
    |> Postgresql.Insert.on_conflict_do_nothing
    |> command)
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| INSERT INTO "public"."people" ("id") VALUES ($1) ON CONFLICT DO NOTHING |}];
  let update_from =
    Update.(
      table Person.table
      |> from Department.table ~f:(fun person department update ->
        update
        |> set_expr Person.name_column (Department.name department)
        |> where (fun _ -> Person.id person =. Department.person_id department))
      |> command)
  in
  update_from
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {| UPDATE "public"."people" AS t0 SET "name" = t1."name" FROM "public"."departments" AS t1 WHERE (t0."id" = t1."person_id") |}];
  update_from
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {| UPDATE "public"."people" AS t0 SET "name" = t1."name" FROM "public"."departments" AS t1 WHERE (t0."id" = t1."person_id") |}];
  Update.(table Person.table |> default Person.name_column |> all_rows |> command)
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| UPDATE "public"."people" SET "name" = DEFAULT |}]
;;

let%expect_test "DML validation and capability diagnostics" =
  let print_error result =
    match result with
    | Ok _ -> failwith "expected compilation error"
    | Error error -> Stdlib.print_endline (Compile_error.to_string error)
  in
  Insert.(
    rows
      Person.table
      [ (fun row -> row |> set Person.id_column 1L |> set Person.name_column "Ada")
      ; (fun row -> row |> set Person.id_column 2L)
      ]
    |> command)
  |> Compiler.compile_command ~dialect:Dialect.Sqlite
  |> print_error;
  [%expect {| INSERT row 2 assigns columns [id], expected [id, name] |}];
  Insert.(rows Person.table [ Fn.id; Fn.id ] |> command)
  |> Compiler.compile_command ~dialect:Dialect.Sqlite
  |> print_error;
  [%expect {| INSERT row 1 has no assignments |}];
  Insert.(into Person.table |> default Person.id_column |> command)
  |> Compiler.compile_command ~dialect:Dialect.Sqlite
  |> print_error;
  [%expect {| INSERT DEFAULT is not supported by the sqlite dialect |}];
  Insert.(
    into Person.table
    |> default Person.id_column
    |> returning (fun person -> Projection.expr (Person.id person)))
  |> Compiler.compile ~dialect:Dialect.Sqlite
  |> print_error;
  [%expect {| INSERT DEFAULT is not supported by the sqlite dialect |}];
  Update.(table Person.table |> default Person.name_column |> all_rows |> command)
  |> Compiler.compile_command ~dialect:Dialect.Sqlite
  |> print_error;
  [%expect {| UPDATE SET DEFAULT is not supported by the sqlite dialect |}];
  Insert.(
    into Person.table
    |> set Person.id_column 1L
    |> Postgresql.Insert.on_conflict_do_nothing
    |> command)
  |> Compiler.compile_command ~dialect:Dialect.Sqlite
  |> print_error;
  [%expect
    {| Postgresql.Insert.on_conflict_do_nothing is not supported by the sqlite dialect |}]
;;

let%expect_test "conditional UPDATE assignments distinguish omission from NULL" =
  Update.(
    table Person.table
    |> set_opt Person.name_column None
    |> set_opt Person.nickname_column (Some None)
    |> set_expr_opt Person.id_column None
    |> set_expr_opt Person.id_column (Some (Expr.param Db_type.int64 2L))
    |> where (fun person -> Person.id person =$ 1L)
    |> command)
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {| UPDATE "public"."people" SET "nickname" = ?1, "id" = ?2 WHERE ("id" = ?3) |}]
;;
