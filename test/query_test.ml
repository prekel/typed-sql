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

module Event = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "events"
  let occurred_at_column = Column.v_exn table "occurred_at" Db_type.timestamp
  let occurred_at reference = Expr.column reference occurred_at_column
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
    into Person.table |> set Person.id_column 1L |> on_conflict_do_nothing |> command)
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| INSERT INTO "public"."people" ("id") VALUES ($1) ON CONFLICT DO NOTHING |}];
  Insert.(
    into Person.table |> set Person.id_column 1L |> on_conflict_do_nothing |> command)
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| INSERT INTO "public"."people" ("id") VALUES (?1) ON CONFLICT DO NOTHING |}];
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
  [%expect {| UPDATE SET DEFAULT is not supported by the sqlite dialect |}]
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

let%expect_test "portable predicates, CASE, and string expressions" =
  let query =
    Query.(
      from Person.table
      |> where (fun person ->
        Expr.in_ (Person.id person) [ 1L; 2L ]
        &&. Expr.not_in (Person.name person) [ "Linus" ]
        &&. Expr.between (Person.id person) ~lower:1L ~upper:10L
        &&. Expr.is_distinct_from_value (Person.nickname person) None)
      |> select (fun person ->
        Projection.pair
          (Expr.case
             [ Person.name person =$ "Ada", Expr.upper (Person.name person)
             ; Person.name person =$ "Grace", Expr.lower (Person.name person)
             ]
             ~else_:(Expr.concat_value (Person.name person) "!"))
          (Expr.length (Person.name person))))
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT (CASE WHEN (t0."name" = $1) THEN UPPER(t0."name") WHEN (t0."name" = $2) THEN LOWER(t0."name") ELSE (t0."name" || $3) END), CHAR_LENGTH(t0."name") FROM "public"."people" AS t0 WHERE ((t0."id" IN ($4, $5)) AND (t0."name" NOT IN ($6)) AND (t0."id" BETWEEN $7 AND $8) AND (t0."nickname" IS DISTINCT FROM $9)) |}];
  query |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT (CASE WHEN (t0."name" = ?1) THEN UPPER(t0."name") WHEN (t0."name" = ?2) THEN LOWER(t0."name") ELSE (t0."name" || ?3) END), LENGTH(t0."name") FROM "public"."people" AS t0 WHERE ((t0."id" IN (?4, ?5)) AND (t0."name" NOT IN (?6)) AND (t0."id" BETWEEN ?7 AND ?8) AND (t0."nickname" IS NOT ?9)) |}]
;;

let%expect_test "typed arithmetic renders for every numeric representation" =
  let query =
    Query.(
      from Person.table
      |> select (fun person ->
        let int64 = Person.id person in
        let int_ = Expr.param Db_type.int 12 in
        let float = Expr.param Db_type.float 12.0 in
        Projection.map3
          ~f:(fun int64_values int_values float_values ->
            int64_values, int_values, float_values)
          (Projection.all
             (List.map
                [ Expr.Int64.add int64 (Expr.param Db_type.int64 1L)
                ; Expr.Int64.subtract int64 (Expr.param Db_type.int64 2L)
                ; Expr.Int64.multiply int64 (Expr.param Db_type.int64 3L)
                ; Expr.Int64.divide int64 (Expr.param Db_type.int64 4L)
                ]
                ~f:Projection.expr))
          (Projection.all
             (List.map
                [ Expr.Int.add int_ (Expr.param Db_type.int 1)
                ; Expr.Int.subtract int_ (Expr.param Db_type.int 2)
                ; Expr.Int.multiply int_ (Expr.param Db_type.int 3)
                ; Expr.Int.divide int_ (Expr.param Db_type.int 4)
                ]
                ~f:Projection.expr))
          (Projection.all
             (List.map
                [ Expr.Float.add float (Expr.param Db_type.float 1.0)
                ; Expr.Float.subtract float (Expr.param Db_type.float 2.0)
                ; Expr.Float.multiply float (Expr.param Db_type.float 3.0)
                ; Expr.Float.divide float (Expr.param Db_type.float 4.0)
                ]
                ~f:Projection.expr))))
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT (t0."id" + $1), (t0."id" - $2), (t0."id" * $3), (t0."id" / $4), ($5 + $6), ($7 - $8), ($9 * $10), ($11 / $12), ($13 + $14), ($15 - $16), ($17 * $18), ($19 / $20) FROM "public"."people" AS t0 |}];
  query |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT (t0."id" + ?1), (t0."id" - ?2), (t0."id" * ?3), (t0."id" / ?4), (?5 + ?6), (?7 - ?8), (?9 * ?10), (?11 / ?12), (?13 + ?14), (?15 - ?16), (?17 * ?18), (?19 / ?20) FROM "public"."people" AS t0 |}]
;;

let%expect_test "empty membership lists normalize without invalid SQL" =
  Query.(
    from Person.table
    |> where (fun person -> Expr.in_ (Person.id person) [])
    |> select Person.projection)
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."id", t0."name", t0."nickname" FROM "public"."people" AS t0 WHERE FALSE |}];
  Query.(
    from Person.table
    |> where (fun person -> Expr.not_in (Person.id person) [])
    |> select Person.projection)
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect {| SELECT t0."id", t0."name", t0."nickname" FROM "public"."people" AS t0 |}]
;;

let%expect_test "DISTINCT and aggregate queries are portable" =
  let distinct_query =
    Query.(
      from Person.table
      |> distinct
      |> select (fun person -> Projection.expr (Person.name person)))
  in
  distinct_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect {| SELECT DISTINCT t0."name" FROM "public"."people" AS t0 |}];
  distinct_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect {| SELECT DISTINCT t0."name" FROM "public"."people" AS t0 |}];
  let grouped =
    Query.(
      from Person.table
      |> group_by (fun person -> Person.name person)
      |> having (fun _ -> Expr.count_all >$ 0L)
      |> order_by (fun person -> Person.name person) `Asc
      |> select (fun person ->
        Projection.map3
          ~f:(fun name count distinct_count -> name, count, distinct_count)
          (Projection.expr (Person.name person))
          (Projection.expr (Expr.count (Person.id person)))
          (Projection.expr (Expr.count_distinct (Person.nickname person)))))
  in
  grouped |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."name", COUNT(t0."id"), COUNT(DISTINCT t0."nickname") FROM "public"."people" AS t0 GROUP BY t0."name" HAVING (COUNT(*) > $1) ORDER BY t0."name" ASC |}];
  grouped |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."name", COUNT(t0."id"), COUNT(DISTINCT t0."nickname") FROM "public"."people" AS t0 GROUP BY t0."name" HAVING (COUNT(*) > ?1) ORDER BY t0."name" ASC |}]
;;

let%expect_test "GROUP BY accepts the same portable expression in projection" =
  let query =
    Query.(
      from Person.table
      |> group_by (fun person -> Expr.lower (Person.name person))
      |> order_by (fun person -> Expr.lower (Person.name person)) `Asc
      |> select (fun person ->
        Projection.pair (Expr.lower (Person.name person)) Expr.count_all))
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT LOWER(t0."name"), COUNT(*) FROM "public"."people" AS t0 GROUP BY LOWER(t0."name") ORDER BY LOWER(t0."name") ASC |}];
  query |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT LOWER(t0."name"), COUNT(*) FROM "public"."people" AS t0 GROUP BY LOWER(t0."name") ORDER BY LOWER(t0."name") ASC |}];
  let arithmetic =
    Query.(
      from Person.table
      |> group_by (fun person -> Expr.Int64.add (Person.id person) (Person.id person))
      |> select (fun person ->
        Projection.pair
          (Expr.Int64.add (Person.id person) (Person.id person))
          Expr.count_all))
  in
  arithmetic
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {| SELECT (t0."id" + t0."id"), COUNT(*) FROM "public"."people" AS t0 GROUP BY (t0."id" + t0."id") |}];
  arithmetic |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT (t0."id" + t0."id"), COUNT(*) FROM "public"."people" AS t0 GROUP BY (t0."id" + t0."id") |}];
  let concatenated =
    Query.(
      from Person.table
      |> group_by (fun person -> Expr.concat (Person.name person) (Person.name person))
      |> select (fun person ->
        Projection.pair
          (Expr.concat (Person.name person) (Person.name person))
          Expr.count_all))
  in
  concatenated
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {| SELECT (t0."name" || t0."name"), COUNT(*) FROM "public"."people" AS t0 GROUP BY (t0."name" || t0."name") |}];
  concatenated |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT (t0."name" || t0."name"), COUNT(*) FROM "public"."people" AS t0 GROUP BY (t0."name" || t0."name") |}]
;;

let%test_unit "GROUP BY compares every public arithmetic and string function" =
  let check make_expression =
    let query =
      Query.(
        from Person.table
        |> group_by make_expression
        |> select (fun person -> Projection.pair (make_expression person) Expr.count_all))
    in
    List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
      match Compiler.compile ~dialect query with
      | Ok _ -> ()
      | Error error -> failwith (Compile_error.to_string error))
  in
  check (fun person -> Expr.Int64.subtract (Person.id person) (Person.id person));
  check (fun person -> Expr.Int64.multiply (Person.id person) (Person.id person));
  check (fun person -> Expr.Int64.divide (Person.id person) (Person.id person));
  check (fun person -> Expr.upper (Person.name person));
  check (fun person -> Expr.length (Person.name person));
  let expect_ungrouped group projection =
    let query =
      Query.(
        from Person.table
        |> group_by group
        |> select (fun person -> Projection.expr (projection person)))
    in
    match Compiler.compile ~dialect:Dialect.Sqlite query with
    | Error Compile_error.Ungrouped_expression -> ()
    | Error error -> failwith (Compile_error.to_string error)
    | Ok _ -> failwith "different expressions were treated as the same group"
  in
  expect_ungrouped
    (fun person -> Expr.Int64.add (Person.id person) (Person.id person))
    (fun person -> Expr.Int64.subtract (Person.id person) (Person.id person));
  expect_ungrouped
    (fun person -> Expr.lower (Person.name person))
    (fun person -> Expr.upper (Person.name person))
;;

let%expect_test "aggregate validation rejects invalid SQL scopes" =
  let print_error query =
    match Compiler.compile ~dialect:Dialect.Sqlite query with
    | Ok _ -> failwith "expected aggregate validation error"
    | Error error -> Stdlib.print_endline (Compile_error.to_string error)
  in
  Query.(
    from Person.table |> where (fun _ -> Expr.count_all >$ 0L) |> select Person.projection)
  |> print_error;
  [%expect {| aggregate expressions are not allowed in WHERE |}];
  Query.(
    from Person.table
    |> group_by (fun person -> Expr.count (Person.id person))
    |> select (fun _ -> Projection.expr Expr.count_all))
  |> print_error;
  [%expect {| aggregate expressions are not allowed in GROUP BY |}];
  Query.(
    from Person.table
    |> select (fun person ->
      Projection.pair (Person.name person) (Expr.count (Person.id person))))
  |> print_error;
  [%expect {| non-aggregate expression must be present in GROUP BY |}];
  Query.(
    from Person.table |> select (fun _ -> Projection.expr (Expr.count Expr.count_all)))
  |> print_error;
  [%expect {| aggregate expressions cannot be nested |}]
;;

let%expect_test "correlated EXISTS, scalar subquery, and IN subquery" =
  let departments = Query.(from Department.table |> select_scalar Department.person_id) in
  let query =
    Query.(
      from Person.table
      |> where (fun person ->
        Query.(
          from Department.table
          |> where (fun department -> Department.person_id department =. Person.id person)
          |> exists)
        &&. in_subquery (Person.id person) departments)
      |> select (fun person ->
        let department_name =
          Query.(
            from Department.table
            |> where (fun department ->
              Department.person_id department =. Person.id person)
            |> limit 1
            |> select_scalar Department.name)
          |> Expr.scalar_subquery
        in
        Projection.pair (Person.name person) department_name))
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."name", (SELECT t1."name" FROM "public"."departments" AS t1 WHERE (t1."person_id" = t0."id") LIMIT 1) FROM "public"."people" AS t0 WHERE ((EXISTS (SELECT 1 FROM "public"."departments" AS t1 WHERE (t1."person_id" = t0."id"))) AND (t0."id" IN (SELECT t1."person_id" FROM "public"."departments" AS t1))) |}];
  query |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."name", (SELECT t1."name" FROM "public"."departments" AS t1 WHERE (t1."person_id" = t0."id") LIMIT 1) FROM "public"."people" AS t0 WHERE ((EXISTS (SELECT 1 FROM "public"."departments" AS t1 WHERE (t1."person_id" = t0."id"))) AND (t0."id" IN (SELECT t1."person_id" FROM "public"."departments" AS t1))) |}]
;;

let%expect_test "negated subqueries render explicitly" =
  Query.(
    from Person.table
    |> where (fun person ->
      Query.(from Department.table |> not_exists)
      &&. not_in_subquery
            (Person.id person)
            Query.(from Department.table |> select_scalar Department.person_id))
    |> select Person.projection)
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."id", t0."name", t0."nickname" FROM "public"."people" AS t0 WHERE ((NOT EXISTS (SELECT 1 FROM "public"."departments" AS t1)) AND (t0."id" NOT IN (SELECT t1."person_id" FROM "public"."departments" AS t1))) |}]
;;

let%expect_test "typed current timestamp is portable" =
  let query =
    Query.(
      from Event.table
      |> where (fun event -> Event.occurred_at event <=. Expr.current_timestamp)
      |> select (fun event -> Projection.expr (Event.occurred_at event)))
  in
  query |> compile_exn Dialect.Postgresql |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."occurred_at" FROM "public"."events" AS t0 WHERE (t0."occurred_at" <= CURRENT_TIMESTAMP) |}];
  query |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {| SELECT t0."occurred_at" FROM "public"."events" AS t0 WHERE (t0."occurred_at" <= CURRENT_TIMESTAMP) |}];
  Insert.(
    into Event.table
    |> set_expr Event.occurred_at_column Expr.current_timestamp
    |> command)
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| INSERT INTO "public"."events" ("occurred_at") VALUES (CURRENT_TIMESTAMP) |}]
;;

let%test_unit "public edge paths preserve normalized semantics" =
  assert (String.equal (Db_type.name Db_type.timestamp) "timestamp");
  let always =
    Query.(
      from Person.table |> where (fun _ -> Condition.true_) |> select Person.projection)
    |> compile_exn Dialect.Sqlite
  in
  assert (
    String.equal
      (Compiled_query.sql always)
      "SELECT t0.\"id\", t0.\"name\", t0.\"nickname\" FROM \"public\".\"people\" AS t0");
  let distinct_expression =
    Query.(
      from Person.table
      |> where (fun person ->
        Expr.is_distinct_from
          (Person.nickname person)
          (Expr.param (Db_type.option Db_type.text) None))
      |> select Person.projection)
    |> compile_exn Dialect.Postgresql
  in
  assert (
    String.is_substring (Compiled_query.sql distinct_expression) ~substring:"DISTINCT");
  let repeated_having =
    Query.(
      from Person.table
      |> having (fun _ -> Expr.count_all >$ 0L)
      |> having (fun _ -> Expr.count_all <$ 10L)
      |> select (fun _ -> Projection.expr Expr.count_all))
    |> compile_exn Dialect.Sqlite
  in
  assert (String.is_substring (Compiled_query.sql repeated_having) ~substring:" AND ");
  Insert.(rows Person.table [] |> set Person.id_column 7L |> command)
  |> compile_command_exn Dialect.Sqlite
  |> ignore;
  Insert.(rows Person.table [] |> default Person.id_column |> command)
  |> compile_command_exn Dialect.Postgresql
  |> ignore
;;
