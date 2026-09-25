open! Base
open Typed_sql
open Statement_compile
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

module Calendar_day = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "calendar_days"
  let date_column = Column.v_exn table "calendar_date" Db_type.date
  let date reference = Expr.column reference date_column
end

module Resource = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "resources"
  let external_id_column = Column.v_exn table "external_id" Db_type.uuid
  let external_id reference = Expr.column reference external_id_column
end

module Sale = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "sales"
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let quantity_column = Column.v_exn table "quantity" Db_type.int
  let unit_price_column = Column.v_exn table "unit_price" Db_type.float
  let amount_column = Column.v_exn table "amount" Db_type.numeric
  let region_column = Column.v_exn table "region" Db_type.text
  let person_id reference = Expr.column reference person_id_column
  let quantity reference = Expr.column reference quantity_column
  let unit_price reference = Expr.column reference unit_price_column
  let amount reference = Expr.column reference amount_column
  let region reference = Expr.column reference region_column
end

module Blob = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "blobs"
  let value_column = Column.v_exn table "value" Db_type.bytes
  let value reference = Expr.column reference value_column
end

let compile_exn dialect query =
  match Compiler.compile_portable ~dialect query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let compile_postgresql_exn query =
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let rendering_query =
  Query.(
    from Person.table
    |> where (fun person ->
      Condition.true_ &&. (Person.name person =$ "Ada") &&. (Person.id person >$ 10L))
    |> order_by (fun person -> Person.id person) `Desc
    |> limit 20
    |> offset 5
    |> select (fun person -> Projection.pair (Person.id person) (Person.name person)))
;;

let nested_multiset_query =
  Query.(
    from Person.table
    |> select (fun person ->
      let departments =
        Query.(
          from Department.table
          |> where (fun department -> Department.person_id department =. Person.id person)
          |> order_by Department.name `Asc
          |> limit 3
          |> select (fun department -> Projection.expr (Department.name department)))
      in
      Projection.both (Projection.expr (Person.name person)) (Query.multiset departments)))
;;

let aggregate_query =
  Query.(
    from Department.table
    |> select_exactly_one (fun department ->
      Projection.multiset_agg
        ~filter:(Department.person_id department >$ 0L)
        ~order_by:[ Aggregate_order.desc (Department.name department) ]
        (Projection.pair (Department.person_id department) (Department.name department))))
;;

let recursive_aggregate_query =
  Query.(
    from Person.table
    |> select_exactly_one (fun person ->
      let departments =
        Query.(
          from Department.table
          |> where (fun department -> Department.person_id department =. Person.id person)
          |> select (fun department -> Projection.expr (Department.name department)))
      in
      Projection.multiset_agg
        ~order_by:[ Aggregate_order.asc (Person.id person) ]
        (Projection.both
           (Projection.expr (Person.name person))
           (Query.multiset departments))))
;;

(* Golden queries in this file use definition-time constants. [Statement_compile]
   routes compilation through the public [Statement] API. *)
let%test_module "portable query rendering" =
  (module struct
    let%expect_test "PostgreSQL rendering" =
      rendering_query
      |> compile_exn Dialect.Postgresql
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."name"
        FROM "public"."people" AS t0
        WHERE
          (
            (t0."name" = $1)
            AND (t0."id" > $2)
          )
        ORDER BY
          t0."id" DESC
        LIMIT 20
        OFFSET 5
        |}]
    ;;

    let%expect_test "SQLite rendering" =
      rendering_query
      |> compile_exn Dialect.Sqlite
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id",
          t0."name"
        FROM "public"."people" AS t0
        WHERE
          (
            (t0."name" = ?1)
            AND (t0."id" > ?2)
          )
        ORDER BY
          t0."id" DESC
        LIMIT 20
        OFFSET 5
        |}]
    ;;

    let%expect_test "multiset subquery renders in PostgreSQL" =
      nested_multiset_query
      |> compile_exn Dialect.Postgresql
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."name",
          CAST((SELECT COALESCE(JSONB_AGG(JSONB_BUILD_ARRAY(m0."v0")), JSONB_BUILD_ARRAY())
          FROM LATERAL (
            SELECT
              t1."name" AS "v0"
            FROM "public"."departments" AS t1
            WHERE
              (t1."person_id" = t0."id")
            ORDER BY
              t1."name" ASC
            LIMIT 3
          ) AS m0) AS TEXT)
        FROM "public"."people" AS t0
        |}]
    ;;

    let%expect_test "multiset subquery renders in SQLite" =
      nested_multiset_query
      |> compile_exn Dialect.Sqlite
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."name",
          (SELECT COALESCE(JSON_GROUP_ARRAY(JSON_ARRAY(m0."v0")), JSON_ARRAY())
          FROM (
            SELECT
              t1."name" AS "v0"
            FROM "public"."departments" AS t1
            WHERE
              (t1."person_id" = t0."id")
            ORDER BY
              t1."name" ASC
            LIMIT 3
          ) AS m0)
        FROM "public"."people" AS t0
        |}]
    ;;

    let%expect_test "multiset aggregate renders in PostgreSQL" =
      aggregate_query
      |> compile_exn Dialect.Postgresql
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          CAST(
            COALESCE(
              JSONB_AGG(
                JSONB_BUILD_ARRAY(
                  t0."person_id",
                  t0."name"
                )
                ORDER BY t0."name" DESC
              ) FILTER (
                WHERE (t0."person_id" > $1)
              ),
              JSONB_BUILD_ARRAY()
            )
            AS TEXT
          )
        FROM "public"."departments" AS t0
        |}]
    ;;

    let%expect_test "multiset aggregate renders in SQLite" =
      aggregate_query
      |> compile_exn Dialect.Sqlite
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          COALESCE(
            JSON_GROUP_ARRAY(
              JSON_ARRAY(
                t0."person_id",
                t0."name"
              )
              ORDER BY t0."name" DESC
            ) FILTER (
              WHERE (t0."person_id" > ?1)
            ),
            JSON_ARRAY()
          )
        FROM "public"."departments" AS t0
        |}]
    ;;

    let%expect_test "recursive multiset aggregate renders in PostgreSQL" =
      recursive_aggregate_query
      |> compile_exn Dialect.Postgresql
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          CAST(
            COALESCE(
              JSONB_AGG(
                JSONB_BUILD_ARRAY(
                  t0."name",
                  (SELECT COALESCE(JSONB_AGG(JSONB_BUILD_ARRAY(m0."v0")), JSONB_BUILD_ARRAY())
                  FROM LATERAL (
                    SELECT
                      t1."name" AS "v0"
                    FROM "public"."departments" AS t1
                    WHERE
                      (t1."person_id" = t0."id")
                  ) AS m0)
                )
                ORDER BY t0."id" ASC
              ),
              JSONB_BUILD_ARRAY()
            )
            AS TEXT
          )
        FROM "public"."people" AS t0
        |}]
    ;;

    let%expect_test "recursive multiset aggregate renders in SQLite" =
      recursive_aggregate_query
      |> compile_exn Dialect.Sqlite
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          COALESCE(
            JSON_GROUP_ARRAY(
              JSON_ARRAY(
                t0."name",
                JSON((SELECT COALESCE(JSON_GROUP_ARRAY(JSON_ARRAY(m0."v0")), JSON_ARRAY())
                FROM (
                  SELECT
                    t1."name" AS "v0"
                  FROM "public"."departments" AS t1
                  WHERE
                    (t1."person_id" = t0."id")
                ) AS m0))
              )
              ORDER BY t0."id" ASC
            ),
            JSON_ARRAY()
          )
        FROM "public"."people" AS t0
        |}]
    ;;
  end)
;;

let%test_unit "multiset validation rejects unsupported and empty fields" =
  let bytes =
    Query.(
      from Blob.table
      |> select_exactly_one (fun blob ->
        Projection.multiset_agg (Projection.expr (Blob.value blob))))
  in
  (match Compiler.compile ~dialect:Dialect.sqlite bytes with
   | Error
       (Compile_error.Unsupported_multiset_field_type
          ({ path = [ 1 ]; type_name = "bytes" } as detail)) ->
     let message =
       Compile_error.to_string (Compile_error.Unsupported_multiset_field_type detail)
     in
     assert (String.equal message "multiset field 1 has unsupported database type bytes")
   | Error error -> failwith (Compile_error.to_string error)
   | Ok _ -> failwith "bytes multiset unexpectedly compiled");
  let mapped_bytes =
    Db_type.map
      ~name:"mapped_bytes"
      ~encode:Result.return
      ~decode:Result.return
      Db_type.bytes
  in
  let mapped_column = Column.v_exn Blob.table "value" mapped_bytes in
  let mapped =
    Query.(
      from Blob.table
      |> select_exactly_one (fun blob ->
        Projection.multiset_agg (Projection.expr (Expr.column blob mapped_column))))
  in
  (match Compiler.compile ~dialect:Dialect.sqlite mapped with
   | Error (Compile_error.Unsupported_multiset_field_type _) -> ()
   | Error error -> failwith (Compile_error.to_string error)
   | Ok _ -> failwith "mapped bytes multiset unexpectedly compiled");
  let nullable_column = Column.nullable_v_exn Blob.table "value" Db_type.bytes in
  let nullable =
    Query.(
      from Blob.table
      |> select_exactly_one (fun blob ->
        Projection.multiset_agg (Projection.expr (Expr.column blob nullable_column))))
  in
  (match Compiler.compile ~dialect:Dialect.sqlite nullable with
   | Error (Compile_error.Unsupported_multiset_field_type _) -> ()
   | Error error -> failwith (Compile_error.to_string error)
   | Ok _ -> failwith "nullable bytes multiset unexpectedly compiled");
  let empty =
    Query.(
      from Person.table
      |> select_exactly_one (fun _ -> Projection.multiset_agg (Projection.return 1)))
  in
  match Compiler.compile ~dialect:Dialect.sqlite empty with
  | Error Compile_error.Empty_projection -> ()
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "empty multiset projection unexpectedly compiled"
;;

let%test_unit "multiset keeps compound SELECT semantics" =
  let branch name =
    Query.(
      from Person.table
      |> where (fun person -> Person.name person =$ name)
      |> select (fun person -> Projection.expr (Person.name person)))
  in
  let names = Query.union_all (branch "Ada") (branch "Grace") in
  let query =
    Query.(from Person.table |> limit_one |> select (fun _ -> Query.multiset names))
  in
  let sql = query |> compile_exn Dialect.Sqlite |> Compiled_query.sql in
  assert (String.is_substring sql ~substring:"UNION ALL");
  assert (String.is_substring sql ~substring:"AS \"v0\"")
;;

let%test_unit "multiset aggregate boundaries reject only same-level nesting" =
  let nested_aggregate =
    Query.(
      from Person.table
      |> select_exactly_one (fun _ ->
        Projection.multiset_agg (Projection.expr Expr.count_all)))
  in
  (match Compiler.compile ~dialect:Dialect.sqlite nested_aggregate with
   | Error Compile_error.Nested_aggregate -> ()
   | Error error -> failwith (Compile_error.to_string error)
   | Ok _ -> failwith "same-level nested aggregate unexpectedly compiled");
  let inner_aggregate =
    Query.(
      from Department.table
      |> select_exactly_one (fun department ->
        Projection.multiset_agg (Projection.expr (Department.name department))))
  in
  let across_select =
    Query.(
      from Person.table |> limit_one |> select (fun _ -> Query.multiset inner_aggregate))
  in
  let sql = across_select |> compile_exn Dialect.Sqlite |> Compiled_query.sql in
  assert (String.is_substring sql ~substring:"JSON(COALESCE(");
  assert (String.is_substring sql ~substring:"JSON_GROUP_ARRAY")
;;

let%test_unit "nested multiset fields retain JSON identity across a subquery" =
  let departments person =
    Query.(
      from Department.table
      |> where (fun department -> Department.person_id department =. Person.id person)
      |> select (fun department -> Projection.expr (Department.name department)))
  in
  let people =
    Query.(
      from Person.table
      |> select (fun person ->
        Projection.both
          (Projection.expr (Person.name person))
          (Query.multiset (departments person))))
  in
  let query =
    Query.(from Person.table |> limit_one |> select (fun _ -> Query.multiset people))
  in
  let sqlite = query |> compile_exn Dialect.Sqlite |> Compiled_query.sql in
  let postgres = query |> compile_exn Dialect.Postgresql |> Compiled_query.sql in
  assert (String.is_substring sqlite ~substring:"JSON(m0.\"v1\")");
  assert (String.is_substring postgres ~substring:"m0.\"v1\"")
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
    {|
    SELECT
      t0."id",
      t0."name",
      t0."nickname"
    FROM "public"."people" AS t0
    WHERE
      (
        (t0."id" < $1)
        AND (t0."id" <= $2)
        AND (t0."id" > $3)
        AND (t0."id" >= $4)
        AND (t0."id" <> $5)
        AND (t0."name" LIKE $6)
      )
    |}]
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
  match Compiler.compile ~dialect:Dialect.sqlite query with
  | Error (Compile_error.Foreign_source _) -> true
  | _ -> false
;;

let empty_projection_query =
  Query.(from Person.table |> select (fun _ -> Projection.return ()))
;;

let negative_limit_query =
  Query.(from Person.table |> limit (-1) |> select Person.projection)
;;

let%expect_test "empty projections are rejected" =
  (match Compiler.compile ~dialect:Dialect.sqlite empty_projection_query with
   | Ok _ -> failwith "unexpected success"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  [%expect {| SELECT projection must contain at least one expression |}]
;;

let%expect_test "negative limits are rejected" =
  (match Compiler.compile ~dialect:Dialect.sqlite negative_limit_query with
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
  [%expect
    {|
    SELECT
      t0."quoted""name"
    FROM "select" AS t0
    |}]
;;

let inner_join_query =
  Query.(
    from Person.table
    |> inner_join Department.table ~on:(fun person department ->
      Person.id person =. Department.person_id department)
    |> select (fun (person, department) ->
      Projection.map2
        ~f:(fun person_id department_name -> person_id, department_name)
        (Projection.expr (Person.id person))
        (Projection.expr (Department.name department))))
;;

let left_join_query =
  Query.(
    from Person.table
    |> left_join Department.table ~on:(fun person department ->
      Person.id person =. Department.person_id department)
    |> select (fun (person, department) ->
      Projection.map2
        ~f:(fun person_id department_name -> person_id, department_name)
        (Projection.expr (Person.id person))
        (Projection.expr (Department.nullable_name department))))
;;

let%expect_test "inner joins use deterministic aliases" =
  inner_join_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."id",
      t1."name"
    FROM "public"."people" AS t0
    INNER JOIN "public"."departments" AS t1
      ON (t0."id" = t1."person_id")
    |}]
;;

let%expect_test "left joins make the nullable side explicit" =
  left_join_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."id",
      t1."name"
    FROM "public"."people" AS t0
    LEFT JOIN "public"."departments" AS t1
      ON (t0."id" = t1."person_id")
    |}]
;;

let compile_result_exn dialect query =
  match Compiler.compile_portable ~dialect query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let compile_command_exn dialect command =
  match Compiler.compile_portable_command ~dialect command with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let insert_returning_query =
  Insert.(
    into Person.table
    |> set Person.id_column 42L
    |> set Person.name_column "Ada"
    |> returning (fun person -> Projection.expr (Person.id person)))
;;

let update_command =
  Update.(
    table Person.table
    |> set Person.name_column "Grace"
    |> where (fun person -> Person.id person =$ 42L)
    |> command)
;;

let delete_command = Delete.(from Person.table |> all_rows |> command)

let%expect_test "INSERT RETURNING renders portably" =
  insert_returning_query
  |> compile_result_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" (
      "id",
      "name"
    )
    VALUES
      ($1, $2)
    RETURNING
      "id"
    |}]
;;

let%expect_test "UPDATE renders through the SQLite command path" =
  update_command
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    UPDATE "public"."people"
    SET
      "name" = ?1
    WHERE
      ("id" = ?2)
    |}]
;;

let%expect_test "DELETE renders through the PostgreSQL command path" =
  delete_command
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect {| DELETE FROM "public"."people" |}]
;;

let multi_row_insert =
  Insert.(
    rows
      Person.table
      [ (fun row -> row |> set Person.id_column 1L |> set Person.name_column "Ada")
      ; (fun row -> row |> set Person.name_column "Grace" |> set Person.id_column 2L)
      ]
    |> command)
;;

let default_insert =
  Insert.(
    into Person.table
    |> default Person.id_column
    |> set Person.name_column "Ada"
    |> command)
;;

let insert_do_nothing =
  Insert.(
    into Person.table |> set Person.id_column 1L |> on_conflict_do_nothing |> command)
;;

let conflict_target = Insert.Conflict_target.column Person.id_column

let targeted_do_nothing =
  Insert.(
    into Person.table
    |> set Person.id_column 1L
    |> on_conflict conflict_target
    |> do_nothing
    |> command)
;;

let do_update_insert =
  Insert.(
    into Person.table
    |> set Person.id_column 1L
    |> set Person.name_column "Ada"
    |> on_conflict conflict_target
    |> do_update (fun ~existing ~excluded ->
      Conflict_update.(
        empty
        |> set_expr
             Person.name_column
             (Expr.concat
                (Person.name existing)
                (Expr.concat_value (Person.name excluded) "!"))
        |> set Person.id_column 2L))
    |> returning (fun person -> Projection.pair (Person.id person) (Person.name person)))
;;

let update_from_command =
  Update.(
    table Person.table
    |> from Department.table ~f:(fun person department update ->
      update
      |> set_expr Person.name_column (Department.name department)
      |> where (fun _ -> Person.id person =. Department.person_id department))
    |> command)
;;

let default_update_command =
  Update.(table Person.table |> default Person.name_column |> all_rows |> command)
;;

let compile_default_command_exn command =
  Compiler.compile_command ~dialect:Dialect.postgresql command |> function
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let%expect_test "multi-row INSERT renders in PostgreSQL" =
  multi_row_insert
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" (
      "id",
      "name"
    )
    VALUES
      ($1, $2),
      ($3, $4)
    |}]
;;

let%expect_test "multi-row INSERT renders in SQLite" =
  multi_row_insert
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" (
      "id",
      "name"
    )
    VALUES
      (?1, ?2),
      (?3, ?4)
    |}]
;;

let%expect_test "INSERT DEFAULT renders in PostgreSQL" =
  default_insert
  |> compile_default_command_exn
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" (
      "id",
      "name"
    )
    VALUES
      (DEFAULT, $1)
    |}]
;;

let%expect_test "unscoped ON CONFLICT DO NOTHING renders in PostgreSQL" =
  insert_do_nothing
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" (
      "id"
    )
    VALUES
      ($1)
    ON CONFLICT DO NOTHING
    |}]
;;

let%expect_test "targeted ON CONFLICT DO NOTHING renders in PostgreSQL" =
  targeted_do_nothing
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" (
      "id"
    )
    VALUES
      ($1)
    ON CONFLICT (
      "id"
    )
    DO NOTHING
    |}]
;;

let%expect_test "UPDATE conflict action renders in PostgreSQL" =
  do_update_insert
  |> compile_result_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" AS t0 (
      "id",
      "name"
    )
    VALUES
      ($1, $2)
    ON CONFLICT (
      "id"
    )
    DO UPDATE
    SET
      "name" = (t0."name" || (excluded."name" || $3)),
      "id" = $4
    RETURNING
      "id",
      "name"
    |}]
;;

let%expect_test "UPDATE conflict action renders in SQLite" =
  do_update_insert
  |> compile_result_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" AS t0 (
      "id",
      "name"
    )
    VALUES
      (?1, ?2)
    ON CONFLICT (
      "id"
    )
    DO UPDATE
    SET
      "name" = (t0."name" || (excluded."name" || ?3)),
      "id" = ?4
    RETURNING
      "id",
      "name"
    |}]
;;

let%expect_test "unscoped ON CONFLICT DO NOTHING renders in SQLite" =
  insert_do_nothing
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."people" (
      "id"
    )
    VALUES
      (?1)
    ON CONFLICT DO NOTHING
    |}]
;;

let%expect_test "UPDATE FROM renders in PostgreSQL" =
  update_from_command
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    UPDATE "public"."people" AS t0
    SET
      "name" = t1."name"
    FROM "public"."departments" AS t1
    WHERE
      (t0."id" = t1."person_id")
    |}]
;;

let%expect_test "UPDATE FROM renders in SQLite" =
  update_from_command
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    UPDATE "public"."people" AS t0
    SET
      "name" = t1."name"
    FROM "public"."departments" AS t1
    WHERE
      (t0."id" = t1."person_id")
    |}]
;;

let%expect_test "UPDATE DEFAULT renders in PostgreSQL" =
  default_update_command
  |> compile_default_command_exn
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    UPDATE "public"."people"
    SET
      "name" = DEFAULT
    |}]
;;

let print_compilation_error result =
  match result with
  | Ok _ -> failwith "expected compilation error"
  | Error error -> Stdlib.print_endline (Compile_error.to_string error)
;;

let incomplete_insert_rows_error =
  Insert.(
    rows
      Person.table
      [ (fun row -> row |> set Person.id_column 1L |> set Person.name_column "Ada")
      ; (fun row -> row |> set Person.id_column 2L)
      ]
    |> command)
  |> Compiler.compile_command ~dialect:Dialect.sqlite
;;

let empty_insert_row_error =
  Insert.(rows Person.table [ Fn.id; Fn.id ] |> command)
  |> Compiler.compile_command ~dialect:Dialect.sqlite
;;

let duplicate_conflict_target_error =
  let duplicate_target =
    Insert.Conflict_target.(column Person.id_column |> add Person.id_column)
  in
  Insert.(
    into Person.table
    |> set Person.id_column 1L
    |> on_conflict duplicate_target
    |> do_nothing
    |> command)
  |> Compiler.compile_command ~dialect:Dialect.postgresql
;;

let empty_conflict_update_error =
  Insert.(
    into Person.table
    |> set Person.id_column 1L
    |> on_conflict (Conflict_target.column Person.id_column)
    |> do_update (fun ~existing:_ ~excluded:_ -> Conflict_update.empty)
    |> command)
  |> Compiler.compile_command ~dialect:Dialect.sqlite
;;

let%expect_test "incomplete multi-row INSERT diagnostic" =
  print_compilation_error incomplete_insert_rows_error;
  [%expect {| INSERT row 2 assigns columns [id], expected [id, name] |}]
;;

let%expect_test "empty INSERT row diagnostic" =
  print_compilation_error empty_insert_row_error;
  [%expect {| INSERT row 1 has no assignments |}]
;;

let%expect_test "duplicate conflict target diagnostic" =
  print_compilation_error duplicate_conflict_target_error;
  [%expect {| ON CONFLICT target contains column id more than once |}]
;;

let%expect_test "empty conflict update diagnostic" =
  print_compilation_error empty_conflict_update_error;
  [%expect {| ON CONFLICT DO UPDATE must assign at least one column |}]
;;

let%expect_test "conditional UPDATE assignments distinguish omission from NULL" =
  Update.(
    table Person.table
    |> set_opt Person.name_column None
    |> set_opt Person.nickname_column (Some None)
    |> set_expr_opt Person.id_column None
    |> set_expr_opt Person.id_column (Some (Expr.constant Db_type.int64 2L))
    |> where (fun person -> Person.id person =$ 1L)
    |> command)
  |> compile_command_exn Dialect.Sqlite
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    UPDATE "public"."people"
    SET
      "nickname" = ?1,
      "id" = ?2
    WHERE
      ("id" = ?3)
    |}]
;;

let portable_predicates_query =
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
;;

let%expect_test "portable predicates and CASE render in PostgreSQL" =
  portable_predicates_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (CASE
        WHEN (t0."name" = $1) THEN UPPER(t0."name")
        WHEN (t0."name" = $2) THEN LOWER(t0."name")
        ELSE (t0."name" || $3)
      END),
      CHAR_LENGTH(t0."name")
    FROM "public"."people" AS t0
    WHERE
      (
        (t0."id" IN (
          $4,
          $5
        ))
        AND (t0."name" NOT IN ($6))
        AND (t0."id" BETWEEN $7 AND $8)
        AND (t0."nickname" IS DISTINCT FROM $9)
      )
    |}]
;;

let%expect_test "portable predicates and CASE render in SQLite" =
  portable_predicates_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (CASE
        WHEN (t0."name" = ?1) THEN UPPER(t0."name")
        WHEN (t0."name" = ?2) THEN LOWER(t0."name")
        ELSE (t0."name" || ?3)
      END),
      LENGTH(t0."name")
    FROM "public"."people" AS t0
    WHERE
      (
        (t0."id" IN (
          ?4,
          ?5
        ))
        AND (t0."name" NOT IN (?6))
        AND (t0."id" BETWEEN ?7 AND ?8)
        AND (t0."nickname" IS NOT ?9)
      )
    |}]
;;

let arithmetic_query =
  Query.(
    from Person.table
    |> select (fun person ->
      let int64 = Person.id person in
      let int_ = Expr.constant Db_type.int 12 in
      let float = Expr.constant Db_type.float 12.0 in
      let int64_values =
        let open Expr.Int64.Infix in
        [ int64 +. Expr.constant Db_type.int64 1L
        ; int64 -. Expr.constant Db_type.int64 2L
        ; int64 *. Expr.constant Db_type.int64 3L
        ; int64 /. Expr.constant Db_type.int64 4L
        ]
      in
      let int_values =
        let open Expr.Int.Infix in
        [ int_ +. Expr.constant Db_type.int 1
        ; int_ -. Expr.constant Db_type.int 2
        ; int_ *. Expr.constant Db_type.int 3
        ; int_ /. Expr.constant Db_type.int 4
        ]
      in
      let float_values =
        let open Expr.Float.Infix in
        [ float +. Expr.constant Db_type.float 1.0
        ; float -. Expr.constant Db_type.float 2.0
        ; float *. Expr.constant Db_type.float 3.0
        ; float /. Expr.constant Db_type.float 4.0
        ]
      in
      Projection.map3
        ~f:(fun int64_values int_values float_values ->
          int64_values, int_values, float_values)
        (Projection.all (List.map int64_values ~f:Projection.expr))
        (Projection.all (List.map int_values ~f:Projection.expr))
        (Projection.all (List.map float_values ~f:Projection.expr))))
;;

let%expect_test "typed arithmetic renders in PostgreSQL" =
  arithmetic_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (t0."id" + $1),
      (t0."id" - $2),
      (t0."id" * $3),
      (t0."id" / $4),
      ($5 + $6),
      ($7 - $8),
      ($9 * $10),
      ($11 / $12),
      ($13 + $14),
      ($15 - $16),
      ($17 * $18),
      ($19 / $20)
    FROM "public"."people" AS t0
    |}]
;;

let%expect_test "typed arithmetic renders in SQLite" =
  arithmetic_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (t0."id" + ?1),
      (t0."id" - ?2),
      (t0."id" * ?3),
      (t0."id" / ?4),
      (?5 + ?6),
      (?7 - ?8),
      (?9 * ?10),
      (?11 / ?12),
      (?13 + ?14),
      (?15 - ?16),
      (?17 * ?18),
      (?19 / ?20)
    FROM "public"."people" AS t0
    |}]
;;

let empty_in_query =
  Query.(
    from Person.table
    |> where (fun person -> Expr.in_ (Person.id person) [])
    |> select Person.projection)
;;

let empty_not_in_query =
  Query.(
    from Person.table
    |> where (fun person -> Expr.not_in (Person.id person) [])
    |> select Person.projection)
;;

let%expect_test "empty IN list normalizes to false" =
  empty_in_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."id",
      t0."name",
      t0."nickname"
    FROM "public"."people" AS t0
    WHERE
      FALSE
    |}]
;;

let%expect_test "empty NOT IN list removes its predicate" =
  empty_not_in_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."id",
      t0."name",
      t0."nickname"
    FROM "public"."people" AS t0
    |}]
;;

let distinct_query =
  Query.(
    from Person.table
    |> distinct
    |> select (fun person -> Projection.expr (Person.name person)))
;;

let grouped_aggregate_query =
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
;;

let%expect_test "DISTINCT renders in PostgreSQL" =
  distinct_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT DISTINCT
      t0."name"
    FROM "public"."people" AS t0
    |}]
;;

let%expect_test "DISTINCT renders in SQLite" =
  distinct_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT DISTINCT
      t0."name"
    FROM "public"."people" AS t0
    |}]
;;

let%expect_test "grouped aggregates render in PostgreSQL" =
  grouped_aggregate_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name",
      COUNT(t0."id"),
      COUNT(DISTINCT t0."nickname")
    FROM "public"."people" AS t0
    GROUP BY
      t0."name"
    HAVING
      (COUNT(*) > $1)
    ORDER BY
      t0."name" ASC
    |}]
;;

let%expect_test "grouped aggregates render in SQLite" =
  grouped_aggregate_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name",
      COUNT(t0."id"),
      COUNT(DISTINCT t0."nickname")
    FROM "public"."people" AS t0
    GROUP BY
      t0."name"
    HAVING
      (COUNT(*) > ?1)
    ORDER BY
      t0."name" ASC
    |}]
;;

let sales_summary_query =
  Query.Aggregate.(from Sale.table |> where (fun sale -> Sale.quantity sale >$ 0))
  |> Query.aggregate_one (fun sale ->
    let open Aggregate_projection.Let_syntax in
    let%map count = Aggregate_projection.count_all
    and quantity = Aggregate_projection.sum_int (Sale.quantity sale)
    and region = Aggregate_projection.max Db_type.Orderable.text (Sale.region sale) in
    count, quantity, region)
;;

let grouped_sales_query =
  Query.(
    from Sale.table
    |> group_by Sale.region
    |> select (fun sale ->
      Projection.map3
        ~f:(fun region total_price smallest_quantity ->
          region, total_price, smallest_quantity)
        (Projection.expr (Sale.region sale))
        (Projection.expr (Expr.sum_float (Sale.unit_price sale)))
        (Projection.expr (Expr.min Db_type.Orderable.int (Sale.quantity sale)))))
;;

let numeric_sales_query =
  Query.Aggregate.(from Sale.table)
  |> Query.aggregate_one (fun sale ->
    Aggregate_projection.both
      (Postgresql.Numeric_projection.sum_numeric (Sale.amount sale))
      (Postgresql.Numeric_projection.max_numeric (Sale.amount sale)))
;;

let correlated_sales_total_query =
  Query.(
    from Person.table
    |> select (fun person ->
      let total =
        Query.(
          from Sale.table
          |> where (fun sale -> Sale.person_id sale =. Person.id person)
          |> select_scalar (fun sale -> Expr.sum_int (Sale.quantity sale)))
      in
      Projection.pair (Person.name person) (Expr.scalar_subquery total)))
;;

let%expect_test "aggregate_one summarizes filtered rows in PostgreSQL" =
  sales_summary_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COUNT(*),
      SUM(t0."quantity"),
      MAX(t0."region")
    FROM "public"."sales" AS t0
    WHERE
      (t0."quantity" > $1)
    |}]
;;

let%expect_test "aggregate_one summarizes filtered rows in SQLite" =
  sales_summary_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COUNT(*),
      SUM(t0."quantity"),
      MAX(t0."region")
    FROM "public"."sales" AS t0
    WHERE
      (t0."quantity" > ?1)
    |}]
;;

let%expect_test "grouped SUM and MIN render in PostgreSQL" =
  grouped_sales_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."region",
      SUM(t0."unit_price"),
      MIN(t0."quantity")
    FROM "public"."sales" AS t0
    GROUP BY
      t0."region"
    |}]
;;

let%expect_test "grouped SUM and MIN render in SQLite" =
  grouped_sales_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."region",
      SUM(t0."unit_price"),
      MIN(t0."quantity")
    FROM "public"."sales" AS t0
    GROUP BY
      t0."region"
    |}]
;;

let%expect_test "PostgreSQL numeric SUM and MAX preserve numeric SQL" =
  numeric_sales_query
  |> compile_postgresql_exn
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      SUM(t0."amount"),
      MAX(t0."amount")
    FROM "public"."sales" AS t0
    |}]
;;

let%expect_test "correlated SUM subquery renders in SQLite" =
  correlated_sales_total_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name",
      (
        SELECT
          SUM(t1."quantity")
        FROM "public"."sales" AS t1
        WHERE
          (t1."person_id" = t0."id")
      )
    FROM "public"."people" AS t0
    |}]
;;

let%test "aggregate_one can define a portable query_one statement" =
  Statement.Portable.query_one (fun _ -> sales_summary_query) |> Result.is_ok
;;

let%test "numeric aggregate can define a PostgreSQL query_one statement" =
  Statement.For_dialect.query_one ~dialect:Dialect.postgresql (fun _ ->
    numeric_sales_query)
  |> Result.is_ok
;;

let scalar_fallback_query =
  let candidate =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 1L)
      |> limit 1
      |> select_scalar Person.name)
  in
  Query.select_one
    (Expr.coalesce
       (Expr.scalar_subquery candidate)
       ~default:(Expr.constant Db_type.text "unknown"))
;;

let%expect_test "scalar fallback renders without FROM in PostgreSQL" =
  scalar_fallback_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COALESCE((
        SELECT
          t0."name"
        FROM "public"."people" AS t0
        WHERE
          (t0."id" = $1)
        LIMIT 1
      ), $2)
    |}]
;;

let%expect_test "scalar fallback renders without FROM in SQLite" =
  scalar_fallback_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COALESCE((
        SELECT
          t0."name"
        FROM "public"."people" AS t0
        WHERE
          (t0."id" = ?1)
        LIMIT 1
      ), ?2)
    |}]
;;

let source_free_union_query =
  let first = Query.select_one (Expr.constant Db_type.int64 1L) in
  let second = Query.select_one (Expr.constant Db_type.int64 2L) in
  Query.union_all first second
;;

let%expect_test "source-free UNION ALL renders in PostgreSQL" =
  source_free_union_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT *
    FROM (
      SELECT
        $1
    ) AS s0
    UNION ALL
    SELECT *
    FROM (
      SELECT
        $2
    ) AS s0
    |}]
;;

let%expect_test "source-free UNION ALL renders in SQLite" =
  source_free_union_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT *
    FROM (
      SELECT
        ?1
    ) AS s0
    UNION ALL
    SELECT *
    FROM (
      SELECT
        ?2
    ) AS s0
    |}]
;;

let source_free_cte_query =
  let relation =
    Derived_table.create
      ~table:Person.table
      ~columns:(fun person -> Projection.expr (Person.id person))
      (Query.select_one (Expr.constant Db_type.int64 7L))
  in
  let cte = Cte.select relation in
  Cte.with_result cte ~f:(fun person ->
    let value = Query.(from_cte person |> limit 1 |> select_scalar Person.id) in
    Query.select_one
      (Expr.coalesce
         (Expr.scalar_subquery value)
         ~default:(Expr.constant Db_type.int64 0L)))
;;

let%expect_test "source-free SELECT with CTE renders in PostgreSQL" =
  source_free_cte_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    WITH
      "c0" (
        "id"
      ) AS (
        SELECT
          $1
      )
    SELECT
      COALESCE((
        SELECT
          t0."id"
        FROM "c0" AS t0
        LIMIT 1
      ), $2)
    |}]
;;

let%expect_test "source-free SELECT with CTE renders in SQLite" =
  source_free_cte_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    WITH
      "c0" (
        "id"
      ) AS (
        SELECT
          ?1
      )
    SELECT
      COALESCE((
        SELECT
          t0."id"
        FROM "c0" AS t0
        LIMIT 1
      ), ?2)
    |}]
;;

let%test_unit "source-free SELECT rejects a foreign source" =
  let escaped = ref None in
  ignore
    Query.(
      from Person.table
      |> select (fun person ->
        let expression = Person.name person in
        escaped := Some expression;
        Projection.expr expression));
  let query = Query.select_one (Option.value_exn !escaped) in
  match Compiler.compile_portable ~dialect:Dialect.Sqlite query with
  | Error (Compile_error.Foreign_source _) -> ()
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "foreign source was accepted"
;;

let%test_unit "source-free SELECT rejects nested aggregates" =
  let inner = Expr.coalesce (Expr.to_nullable Expr.count_all) ~default:Expr.count_all in
  let query = Query.select_one (Expr.count inner) in
  match Compiler.compile_portable ~dialect:Dialect.Sqlite query with
  | Error Compile_error.Nested_aggregate -> ()
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "nested aggregate was accepted"
;;

let aggregate_coalesce_query =
  Query.(
    from Person.table
    |> select_exactly_one (fun _ ->
      Projection.expr
        (Expr.coalesce
           (Expr.to_nullable Expr.count_all)
           ~default:(Expr.constant Db_type.int64 0L))))
;;

let%expect_test "aggregate COALESCE renders in PostgreSQL" =
  aggregate_coalesce_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COALESCE(COUNT(*), $1)
    FROM "public"."people" AS t0
    |}]
;;

let%expect_test "aggregate COALESCE renders in SQLite" =
  aggregate_coalesce_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COALESCE(COUNT(*), ?1)
    FROM "public"."people" AS t0
    |}]
;;

let coalesce_inside_aggregate_query =
  Query.Aggregate.(from Person.table)
  |> Query.aggregate_one (fun person ->
    Aggregate_projection.count
      (Expr.coalesce
         (Person.nickname person)
         ~default:(Expr.constant Db_type.text "unknown")))
;;

let%expect_test "COALESCE inside an aggregate renders in PostgreSQL" =
  coalesce_inside_aggregate_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COUNT(COALESCE(t0."nickname", $1))
    FROM "public"."people" AS t0
    |}]
;;

let%expect_test "COALESCE inside an aggregate renders in SQLite" =
  coalesce_inside_aggregate_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COUNT(COALESCE(t0."nickname", ?1))
    FROM "public"."people" AS t0
    |}]
;;

let grouped_coalesce_query =
  let expression person =
    Expr.coalesce (Person.nickname person) ~default:(Person.name person)
  in
  Query.(
    from Person.table
    |> group_by expression
    |> select (fun person -> Projection.expr (expression person)))
;;

let%expect_test "grouped COALESCE renders in PostgreSQL" =
  grouped_coalesce_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COALESCE(t0."nickname", t0."name")
    FROM "public"."people" AS t0
    GROUP BY
      COALESCE(t0."nickname", t0."name")
    |}]
;;

let%expect_test "grouped COALESCE renders in SQLite" =
  grouped_coalesce_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      COALESCE(t0."nickname", t0."name")
    FROM "public"."people" AS t0
    GROUP BY
      COALESCE(t0."nickname", t0."name")
    |}]
;;

let%test_unit "SQLite rejects numeric in source-free COALESCE" =
  let value = Decimal.of_string "1.25" |> Option.value_exn in
  let query =
    Query.select_one
      (Expr.coalesce
         (Expr.to_nullable (Expr.constant Db_type.numeric value))
         ~default:(Expr.constant Db_type.numeric value))
  in
  match Compiler.compile ~dialect:Dialect.sqlite query with
  | Error (Compile_error.Unsupported_operation { operation = "numeric"; _ }) -> ()
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "SQLite accepted numeric COALESCE"
;;

let lowered_group_query =
  Query.(
    from Person.table
    |> group_by (fun person -> Expr.lower (Person.name person))
    |> order_by (fun person -> Expr.lower (Person.name person)) `Asc
    |> select (fun person ->
      Projection.pair (Expr.lower (Person.name person)) Expr.count_all))
;;

let arithmetic_group_expression person =
  let open Expr.Int64.Infix in
  Person.id person +. Person.id person
;;

let arithmetic_group_query =
  Query.(
    from Person.table
    |> group_by arithmetic_group_expression
    |> select (fun person ->
      Projection.pair (arithmetic_group_expression person) Expr.count_all))
;;

let concatenated_group_query =
  Query.(
    from Person.table
    |> group_by (fun person -> Expr.concat (Person.name person) (Person.name person))
    |> select (fun person ->
      Projection.pair
        (Expr.concat (Person.name person) (Person.name person))
        Expr.count_all))
;;

let%expect_test "lowered GROUP BY expression is portable to PostgreSQL" =
  lowered_group_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      LOWER(t0."name"),
      COUNT(*)
    FROM "public"."people" AS t0
    GROUP BY
      LOWER(t0."name")
    ORDER BY
      LOWER(t0."name") ASC
    |}]
;;

let%expect_test "lowered GROUP BY expression is portable to SQLite" =
  lowered_group_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      LOWER(t0."name"),
      COUNT(*)
    FROM "public"."people" AS t0
    GROUP BY
      LOWER(t0."name")
    ORDER BY
      LOWER(t0."name") ASC
    |}]
;;

let%expect_test "arithmetic GROUP BY expression is portable to PostgreSQL" =
  arithmetic_group_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (t0."id" + t0."id"),
      COUNT(*)
    FROM "public"."people" AS t0
    GROUP BY
      (t0."id" + t0."id")
    |}]
;;

let%expect_test "arithmetic GROUP BY expression is portable to SQLite" =
  arithmetic_group_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (t0."id" + t0."id"),
      COUNT(*)
    FROM "public"."people" AS t0
    GROUP BY
      (t0."id" + t0."id")
    |}]
;;

let%expect_test "concatenated GROUP BY expression is portable to PostgreSQL" =
  concatenated_group_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (t0."name" || t0."name"),
      COUNT(*)
    FROM "public"."people" AS t0
    GROUP BY
      (t0."name" || t0."name")
    |}]
;;

let%expect_test "concatenated GROUP BY expression is portable to SQLite" =
  concatenated_group_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (t0."name" || t0."name"),
      COUNT(*)
    FROM "public"."people" AS t0
    GROUP BY
      (t0."name" || t0."name")
    |}]
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
      match Compiler.compile_portable ~dialect query with
      | Ok _ -> ()
      | Error error -> failwith (Compile_error.to_string error))
  in
  check (fun person ->
    let open Expr.Int64.Infix in
    Person.id person -. Person.id person);
  check (fun person ->
    let open Expr.Int64.Infix in
    Person.id person *. Person.id person);
  check (fun person ->
    let open Expr.Int64.Infix in
    Person.id person /. Person.id person);
  check (fun person -> Expr.upper (Person.name person));
  check (fun person -> Expr.length (Person.name person));
  let expect_ungrouped group projection =
    let query =
      Query.(
        from Person.table
        |> group_by group
        |> select (fun person -> Projection.expr (projection person)))
    in
    match Compiler.compile ~dialect:Dialect.sqlite query with
    | Error Compile_error.Ungrouped_expression -> ()
    | Error error -> failwith (Compile_error.to_string error)
    | Ok _ -> failwith "different expressions were treated as the same group"
  in
  expect_ungrouped
    (fun person ->
       let open Expr.Int64.Infix in
       Person.id person +. Person.id person)
    (fun person ->
       let open Expr.Int64.Infix in
       Person.id person -. Person.id person);
  expect_ungrouped
    (fun person -> Expr.lower (Person.name person))
    (fun person -> Expr.upper (Person.name person))
;;

let print_aggregate_error query =
  match Compiler.compile ~dialect:Dialect.sqlite query with
  | Ok _ -> failwith "expected aggregate validation error"
  | Error error -> Stdlib.print_endline (Compile_error.to_string error)
;;

let aggregate_in_where_query =
  Query.(
    from Person.table |> where (fun _ -> Expr.count_all >$ 0L) |> select Person.projection)
;;

let aggregate_in_group_query =
  Query.(
    from Person.table
    |> group_by (fun person -> Expr.count (Person.id person))
    |> select (fun _ -> Projection.expr Expr.count_all))
;;

let ungrouped_projection_query =
  Query.(
    from Person.table
    |> select (fun person ->
      Projection.pair (Person.name person) (Expr.count (Person.id person))))
;;

let nested_aggregate_query =
  Query.(
    from Person.table |> select (fun _ -> Projection.expr (Expr.count Expr.count_all)))
;;

let%expect_test "aggregate in WHERE is rejected" =
  print_aggregate_error aggregate_in_where_query;
  [%expect {| aggregate expressions are not allowed in WHERE |}]
;;

let%expect_test "aggregate in GROUP BY is rejected" =
  print_aggregate_error aggregate_in_group_query;
  [%expect {| aggregate expressions are not allowed in GROUP BY |}]
;;

let%expect_test "ungrouped projection is rejected" =
  print_aggregate_error ungrouped_projection_query;
  [%expect {| non-aggregate expression must be present in GROUP BY |}]
;;

let%expect_test "nested aggregate is rejected" =
  print_aggregate_error nested_aggregate_query;
  [%expect {| aggregate expressions cannot be nested |}]
;;

let correlated_subquery_query =
  let departments = Query.(from Department.table |> select_scalar Department.person_id) in
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
          |> where (fun department -> Department.person_id department =. Person.id person)
          |> limit 1
          |> select_scalar Department.name)
        |> Expr.scalar_subquery
      in
      Projection.pair (Person.name person) department_name))
;;

let%expect_test "correlated subqueries render in PostgreSQL" =
  correlated_subquery_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name",
      (
        SELECT
          t1."name"
        FROM "public"."departments" AS t1
        WHERE
          (t1."person_id" = t0."id")
        LIMIT 1
      )
    FROM "public"."people" AS t0
    WHERE
      (
        (EXISTS (
          SELECT
            1
          FROM "public"."departments" AS t1
          WHERE
            (t1."person_id" = t0."id")
        ))
        AND (t0."id" IN (
          SELECT
            t1."person_id"
          FROM "public"."departments" AS t1
        ))
      )
    |}]
;;

let%expect_test "correlated subqueries render in SQLite" =
  correlated_subquery_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name",
      (
        SELECT
          t1."name"
        FROM "public"."departments" AS t1
        WHERE
          (t1."person_id" = t0."id")
        LIMIT 1
      )
    FROM "public"."people" AS t0
    WHERE
      (
        (EXISTS (
          SELECT
            1
          FROM "public"."departments" AS t1
          WHERE
            (t1."person_id" = t0."id")
        ))
        AND (t0."id" IN (
          SELECT
            t1."person_id"
          FROM "public"."departments" AS t1
        ))
      )
    |}]
;;

let unbounded_scalar_query =
  let scalar = Query.(from Department.table |> select_scalar Department.name) in
  Query.(
    from Person.table |> select (fun _ -> Projection.expr (Expr.scalar_subquery scalar)))
;;

let zero_limit_scalar_query =
  Query.(
    from Person.table
    |> select (fun _ ->
      Projection.expr
        (Expr.scalar_subquery
           Query.(from Department.table |> limit 0 |> select_scalar Department.name))))
;;

let aggregate_scalar_query =
  Query.(
    from Person.table
    |> select (fun _ ->
      Projection.expr
        (Expr.scalar_subquery
           Query.(from Department.table |> select_scalar (fun _ -> Expr.count_all)))))
;;

let nullable_scalar_query =
  Query.(
    from Person.table
    |> select (fun _ ->
      Projection.expr
        (Expr.scalar_subquery_nullable
           Query.(
             from Department.table
             |> limit 1
             |> select_scalar (fun department ->
               Expr.to_nullable (Department.name department))))))
;;

let%expect_test "unbounded scalar subquery requires a cardinality proof" =
  (match Compiler.compile ~dialect:Dialect.sqlite unbounded_scalar_query with
   | Ok _ -> failwith "unbounded scalar subquery unexpectedly compiled"
   | Error error -> Stdlib.print_endline (Compile_error.to_string error));
  [%expect {| scalar subquery requires LIMIT 0/1 or a local aggregate without GROUP BY |}]
;;

let%expect_test "zero-limit scalar subquery renders in PostgreSQL" =
  zero_limit_scalar_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (
        SELECT
          t1."name"
        FROM "public"."departments" AS t1
        LIMIT 0
      )
    FROM "public"."people" AS t0
    |}]
;;

let%expect_test "aggregate scalar subquery renders in SQLite" =
  aggregate_scalar_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      (
        SELECT
          COUNT(*)
        FROM "public"."departments" AS t1
      )
    FROM "public"."people" AS t0
    |}]
;;

let%test_unit "nullable scalar subquery compiles with a bound" =
  nullable_scalar_query |> compile_exn Dialect.Sqlite |> ignore
;;

let%expect_test "empty CASE normalizes to its else expression" =
  Query.(
    from Person.table
    |> select (fun person -> Projection.expr (Expr.case [] ~else_:(Person.name person))))
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name"
    FROM "public"."people" AS t0
    |}]
;;

let having_constant_query =
  Query.(
    from Person.table
    |> Postgresql.Query.having (fun _ -> Condition.true_)
    |> select (fun _ -> Projection.expr (Expr.constant Db_type.int 1)))
;;

let having_ungrouped_query =
  Query.(
    from Person.table
    |> Postgresql.Query.having (fun person -> Person.id person >$ 0L)
    |> select (fun _ -> Projection.expr Expr.count_all))
;;

let%expect_test "HAVING establishes aggregate context" =
  having_constant_query
  |> Compiler.compile ~dialect:Dialect.postgresql
  |> ( function
   | Ok compiled -> compiled
   | Error error -> failwith (Compile_error.to_string error) )
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      $1
    FROM "public"."people" AS t0
    HAVING
      TRUE
    |}]
;;

let%test_unit "HAVING rejects an ungrouped column in a local aggregate" =
  match Compiler.compile ~dialect:Dialect.postgresql having_ungrouped_query with
  | Error Compile_error.Ungrouped_expression -> ()
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "ungrouped HAVING column unexpectedly compiled"
;;

let%test_unit
    "scalar aggregate proofs and nested SQLite capability checks use public builders"
  =
  let compile query =
    match Compiler.compile ~dialect:Dialect.sqlite query with
    | Ok _ -> ()
    | Error error -> failwith (Compile_error.to_string error)
  in
  let counted =
    Query.(
      from Department.table
      |> select_scalar (fun department -> Expr.count (Department.name department)))
  in
  compile
    Query.(
      from Person.table
      |> select (fun _ -> Projection.expr (Expr.scalar_subquery counted)));
  let counted_distinct =
    Query.(
      from Department.table
      |> inner_join Person.table ~on:(fun _ _ -> Condition.true_)
      |> select_scalar (fun (_, person) -> Expr.count_distinct (Person.id person)))
  in
  compile
    Query.(
      from Person.table
      |> select (fun _ -> Projection.expr (Expr.scalar_subquery counted_distinct)));
  let unsupported_scalar =
    Expr.scalar_subquery
      Query.(
        from Department.table
        |> Postgresql.Query.having (fun _ -> Condition.true_)
        |> limit 1
        |> select_scalar (fun _ -> Expr.constant Db_type.text "fallback"))
  in
  let command =
    Update.(
      table Person.table
      |> set_expr Person.nickname_column unsupported_scalar
      |> all_rows
      |> command)
  in
  (match Compiler.compile_command ~dialect:Dialect.postgresql command with
   | Ok _ -> ()
   | Error error -> failwith (Compile_error.to_string error));
  let returning =
    Update.(
      table Person.table
      |> set Person.name_column "Ada"
      |> all_rows
      |> returning (fun _ -> Projection.expr unsupported_scalar))
  in
  match Compiler.compile ~dialect:Dialect.postgresql returning with
  | Ok _ -> ()
  | Error error -> failwith (Compile_error.to_string error)
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
    {|
    SELECT
      t0."id",
      t0."name",
      t0."nickname"
    FROM "public"."people" AS t0
    WHERE
      (
        (NOT EXISTS (
          SELECT
            1
          FROM "public"."departments" AS t1
        ))
        AND (t0."id" NOT IN (
          SELECT
            t1."person_id"
          FROM "public"."departments" AS t1
        ))
      )
    |}]
;;

let current_timestamp_query =
  Query.(
    from Event.table
    |> where (fun event -> Event.occurred_at event <=. Expr.current_timestamp)
    |> select (fun event -> Projection.expr (Event.occurred_at event)))
;;

let current_timestamp_insert =
  Insert.(
    into Event.table
    |> set_expr Event.occurred_at_column Expr.current_timestamp
    |> command)
;;

let%expect_test "current timestamp renders in PostgreSQL SELECT" =
  current_timestamp_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."occurred_at"
    FROM "public"."events" AS t0
    WHERE
      (t0."occurred_at" <= CURRENT_TIMESTAMP)
    |}]
;;

let%expect_test "current timestamp renders in SQLite SELECT" =
  current_timestamp_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."occurred_at"
    FROM "public"."events" AS t0
    WHERE
      (t0."occurred_at" <= CURRENT_TIMESTAMP)
    |}]
;;

let%expect_test "current timestamp renders in PostgreSQL INSERT" =
  current_timestamp_insert
  |> compile_command_exn Dialect.Postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "public"."events" (
      "occurred_at"
    )
    VALUES
      (CURRENT_TIMESTAMP)
    |}]
;;

let calendar_date = Date.of_ymd_exn ~year:2026 ~month:9 ~day:12

let calendar_date_query =
  Query.(
    from Calendar_day.table
    |> where (fun day -> Calendar_day.date day =$ calendar_date)
    |> select (fun day -> Projection.expr (Calendar_day.date day)))
;;

let%expect_test "calendar date renders in PostgreSQL" =
  calendar_date_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."calendar_date"
    FROM "public"."calendar_days" AS t0
    WHERE
      (t0."calendar_date" = $1)
    |}]
;;

let%expect_test "calendar date renders in SQLite" =
  calendar_date_query
  |> compile_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."calendar_date"
    FROM "public"."calendar_days" AS t0
    WHERE
      (t0."calendar_date" = ?1)
    |}]
;;

let external_uuid = Uuid.of_string_exn "550e8400-e29b-41d4-a716-446655440000"

let uuid_query =
  Query.(
    from Resource.table
    |> where (fun resource -> Resource.external_id resource =$ external_uuid)
    |> select (fun resource -> Projection.expr (Resource.external_id resource)))
;;

let%expect_test "UUID renders in PostgreSQL" =
  uuid_query
  |> compile_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."external_id"
    FROM "public"."resources" AS t0
    WHERE
      (t0."external_id" = $1)
    |}]
;;

let%expect_test "UUID renders in SQLite" =
  uuid_query |> compile_exn Dialect.Sqlite |> Compiled_query.sql |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."external_id"
    FROM "public"."resources" AS t0
    WHERE
      (t0."external_id" = ?1)
    |}]
;;

let%test_unit "public edge paths preserve normalized semantics" =
  assert (String.equal (Db_type.name Db_type.timestamp) "timestamp");
  let always =
    Query.(
      from Person.table |> where (fun _ -> Condition.true_) |> select Person.projection)
    |> compile_exn Dialect.Sqlite
  in
  let without_condition =
    Query.(from Person.table |> select Person.projection) |> compile_exn Dialect.Sqlite
  in
  assert (String.equal (Compiled_query.sql always) (Compiled_query.sql without_condition));
  let distinct_expression =
    Query.(
      from Person.table
      |> where (fun person ->
        Expr.is_distinct_from
          (Person.nickname person)
          (Expr.constant (Db_type.option Db_type.text) None))
      |> select Person.projection)
    |> compile_exn Dialect.Postgresql
  in
  assert (
    String.is_substring (Compiled_query.sql distinct_expression) ~substring:"DISTINCT");
  let repeated_having =
    Query.(
      from Person.table
      |> Postgresql.Query.having (fun _ -> Expr.count_all >$ 0L)
      |> Postgresql.Query.having (fun _ -> Expr.count_all <$ 10L)
      |> select (fun _ -> Projection.expr Expr.count_all))
    |> Compiler.compile ~dialect:Dialect.postgresql
    |> function
    | Ok compiled -> compiled
    | Error error -> failwith (Compile_error.to_string error)
  in
  assert (String.is_substring (Compiled_query.sql repeated_having) ~substring:"AND ");
  Insert.(rows Person.table [] |> set Person.id_column 7L |> command)
  |> compile_command_exn Dialect.Sqlite
  |> ignore;
  Insert.(rows Person.table [] |> default Person.id_column |> command)
  |> Compiler.compile_command ~dialect:Dialect.postgresql
  |> ( function
   | Ok compiled -> compiled
   | Error error -> failwith (Compile_error.to_string error) )
  |> ignore
;;
