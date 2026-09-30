open! Base
open Typed_sql
open Statement_compile
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column
  let projection reference = Projection.pair (id reference) (name reference)
end

module Selected_person = struct
  type row

  let table : row Table.t = Table.v_exn "selected_people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column
  let nullable_name reference = Expr.nullable_column reference name_column
  let projection reference = Projection.pair (id reference) (name reference)
end

module Number = struct
  type row

  let table : row Table.t = Table.v_exn "numbers"
  let value_column = Column.v_exn table "value" Db_type.int64
  let value reference = Expr.column reference value_column
end

let active_people =
  Derived_table.create
    ~table:Selected_person.table
    ~columns:Selected_person.projection
    Query.(
      from Person.table
      |> where (fun person -> Person.name person =$ "Ada")
      |> select Person.projection)
;;

let inferred_active_people : (_, _, Dialect.portable) Derived_table.inferred =
  Query.(
    from Person.table
    |> where (fun person -> Person.name person =$ "Ada")
    |> select_relation (fun person ->
      Derived_table.Fields.pair (Person.id person) (Person.name person)))
;;

let compile_portable_exn dialect query =
  match Compiler.compile_portable ~dialect query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let compile_dialect_exn dialect query =
  match Compiler.compile ~dialect query with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let compile_dialect_command_exn dialect command =
  match Compiler.compile_command ~dialect command with
  | Ok compiled -> compiled
  | Error error -> failwith (Compile_error.to_string error)
;;

let%test_module "typed VALUES sources" =
  (module struct
    module Values_source = struct
      type row

      let table : row Table.t = Table.v_exn "selected_ids"
      let id_column = Column.v_exn table "id" Db_type.int64
      let label_column = Column.v_exn table "label" Db_type.text
      let id reference = Expr.column reference id_column
      let label reference = Expr.column reference label_column
      let columns reference = Projection.pair (id reference) (label reference)
    end

    let selected_ids : (Values_source.row, Dialect.portable) Values.t =
      Values.create
        ~table:Values_source.table
        ~columns:Values_source.columns
        ~first:
          (Values.Row.pair
             (Expr.constant Db_type.int64 2L)
             (Expr.constant Db_type.text "two"))
        ~rest:
          [ Values.Row.pair
              (Expr.constant Db_type.int64 3L)
              (Expr.constant Db_type.text "three")
          ]
    ;;

    let canonical_sql sql =
      [ "$1", "?"
      ; "$2", "?"
      ; "$3", "?"
      ; "$4", "?"
      ; "?1", "?"
      ; "?2", "?"
      ; "?3", "?"
      ; "?4", "?"
      ]
      |> List.fold ~init:sql ~f:(fun sql (pattern, replacement) ->
        String.substr_replace_all sql ~pattern ~with_:replacement)
      |> String.filter ~f:(fun character -> not (Char.is_whitespace character))
    ;;

    let compile_selected_ids dialect =
      Query.(
        from_values selected_ids
        |> select (fun selected -> Values_source.columns selected))
      |> compile_portable_exn dialect
    ;;

    let compile_values values =
      Query.(
        from_values values
        |> select (fun selected -> Projection.expr (Values_source.id selected)))
      |> Compiler.compile_portable ~dialect:Dialect.Sqlite
    ;;

    let%test_unit "typed VALUES renders the same portable relation shape" =
      let expected =
        "SELECTt0.\"id\",t0.\"label\"FROM(SELECT\"v\".\"column1\"AS\"id\",\"v\".\"column2\"AS\"label\"FROM(VALUES(?,?),(?,?))AS\"v\")ASt0"
      in
      let postgresql = compile_selected_ids Dialect.Postgresql in
      let sqlite = compile_selected_ids Dialect.Sqlite in
      assert (String.equal (canonical_sql (Compiled_query.sql postgresql)) expected);
      assert (String.equal (canonical_sql (Compiled_query.sql sqlite)) expected);
      assert (
        Int.equal (String.count (Compiled_query.sql postgresql) ~f:(Char.equal '$')) 4);
      assert (Int.equal (String.count (Compiled_query.sql sqlite) ~f:(Char.equal '?')) 4)
    ;;

    let%test_unit "typed VALUES sources support inner and left joins" =
      let inner =
        Query.(
          from Person.table
          |> inner_join_values selected_ids ~on:(fun person selected ->
            Person.id person =. Values_source.id selected)
          |> select (fun (person, selected) ->
            Projection.pair (Person.name person) (Values_source.label selected)))
        |> compile_portable_exn Dialect.Sqlite
        |> Compiled_query.sql
      in
      assert (String.is_substring inner ~substring:"INNER JOIN (SELECT");
      assert (String.is_substring inner ~substring:"ON (t0.\"id\" = t1.\"id\")");
      let left =
        Query.(
          from Person.table
          |> left_join_values selected_ids ~on:(fun person selected ->
            Person.id person =. Values_source.id selected)
          |> select (fun (person, selected) ->
            Projection.pair
              (Person.name person)
              (Expr.nullable_column selected Values_source.label_column)))
        |> compile_portable_exn Dialect.Postgresql
      in
      assert (String.is_substring (Compiled_query.sql left) ~substring:"LEFT JOIN (SELECT")
    ;;

    let%test_unit "dynamic VALUES reports the row number and expected width" =
      let too_wide =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:Values_source.columns
          ~rows:
            [ [ Values.Cell.expr (Expr.constant Db_type.int64 1L)
              ; Values.Cell.expr (Expr.constant Db_type.text "one")
              ; Values.Cell.expr (Expr.constant Db_type.bool true)
              ]
            ]
      in
      match compile_values too_wide with
      | Error
          (Compile_error.Mismatched_values_row_arity { row = 1; expected = 2; actual = 3 }
           as error) ->
        assert (
          String.equal
            (Compile_error.to_string error)
            "VALUES row 1 has 3 fields, expected 2")
      | _ -> failwith "VALUES row with the wrong width was accepted"
    ;;

    let%test_unit "dynamic VALUES reports incompatible database types" =
      let wrong_type =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:Values_source.columns
          ~rows:
            [ [ Values.Cell.expr (Expr.constant Db_type.int64 1L)
              ; Values.Cell.expr (Expr.constant Db_type.bool true)
              ]
            ]
      in
      match compile_values wrong_type with
      | Error (Compile_error.Mismatched_values_row_types { row = 1; _ } as error) ->
        assert (
          String.equal
            (Compile_error.to_string error)
            "VALUES row 1 has types [int64, bool], expected [int64, text]")
      | _ -> failwith "VALUES row with an incompatible database type was accepted"
    ;;

    let%test_unit "empty dynamic VALUES has an explicit compilation error" =
      let values =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:Values_source.columns
          ~rows:[]
      in
      match compile_values values with
      | Error (Compile_error.Empty_values_rows as error) ->
        assert (
          String.equal
            (Compile_error.to_string error)
            "VALUES relation must contain at least one row")
      | _ -> failwith "empty VALUES relation was accepted"
    ;;

    let%test_unit "VALUES requires at least one declared column" =
      let values =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:(fun _ -> Projection.return ())
          ~rows:[ [ Values.Cell.expr (Expr.constant Db_type.int64 1L) ] ]
      in
      match compile_values values with
      | Error (Compile_error.Empty_values_columns as error) ->
        assert (
          String.equal
            (Compile_error.to_string error)
            "VALUES relation must declare at least one column")
      | _ -> failwith "VALUES relation without columns was accepted"
    ;;

    let%test_unit "VALUES descriptors must contain direct columns" =
      let values =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:(fun _ -> Projection.expr (Expr.constant Db_type.int64 1L))
          ~rows:[ [ Values.Cell.expr (Expr.constant Db_type.int64 1L) ] ]
      in
      match compile_values values with
      | Error (Compile_error.Invalid_relation_column 1) -> ()
      | _ -> failwith "computed VALUES descriptor was accepted"
    ;;

    let%test_unit "VALUES descriptors reject duplicate column names" =
      let values =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:(fun selected ->
            Projection.pair (Values_source.id selected) (Values_source.id selected))
          ~rows:
            [ [ Values.Cell.expr (Expr.constant Db_type.int64 1L)
              ; Values.Cell.expr (Expr.constant Db_type.int64 2L)
              ]
            ]
      in
      match compile_values values with
      | Error (Compile_error.Duplicate_relation_column _) -> ()
      | _ -> failwith "duplicate VALUES descriptor column was accepted"
    ;;

    let%test_unit "VALUES rows reject aggregate expressions" =
      let values =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:(fun selected -> Projection.expr (Values_source.id selected))
          ~rows:[ [ Values.Cell.expr Expr.count_all ] ]
      in
      match compile_values values with
      | Error (Compile_error.Aggregate_not_allowed "VALUES") -> ()
      | _ -> failwith "aggregate VALUES expression was accepted"
    ;;

    let%test "VALUES cells permit an independent scalar subquery" =
      let first_person_id =
        Query.(from Person.table |> limit 1 |> select_scalar Person.id)
      in
      let values =
        Values.create_dynamic
          ~table:Values_source.table
          ~columns:(fun selected -> Projection.expr (Values_source.id selected))
          ~rows:
            [ [ Values.Cell.expr
                  (Expr.coalesce
                     (Expr.scalar_subquery first_person_id)
                     ~default:(Expr.constant Db_type.int64 0L))
              ]
            ]
      in
      Result.is_ok (compile_values values)
    ;;

    let%test_unit "SQLite rejects numeric VALUES cells before rendering" =
      let module Numeric_source = struct
        type row

        let table : row Table.t = Table.v_exn "numeric_values"
        let value_column = Column.v_exn table "value" Db_type.numeric
        let value row = Expr.column row value_column
      end
      in
      let decimal = Decimal.of_string "1.25" |> Option.value_exn in
      let values =
        Values.create
          ~table:Numeric_source.table
          ~columns:(fun row -> Projection.expr (Numeric_source.value row))
          ~first:(Values.Row.expr (Expr.constant Db_type.numeric decimal))
          ~rest:[]
      in
      let query =
        Query.(
          from_values values
          |> select (fun row -> Projection.expr (Numeric_source.value row)))
      in
      (match Compiler.compile ~dialect:Dialect.postgresql query with
       | Ok _ -> ()
       | Error error -> failwith (Compile_error.to_string error));
      match Compiler.compile ~dialect:Dialect.sqlite query with
      | Error (Compile_error.Unsupported_operation { operation = "numeric"; _ }) -> ()
      | Error error -> failwith (Compile_error.to_string error)
      | Ok _ -> failwith "SQLite accepted numeric VALUES cells"
    ;;

    let%test_unit "VALUES rows reject references to outer query sources" =
      let escaped = ref None in
      ignore
        Query.(
          from Person.table
          |> select (fun person ->
            escaped := Some person;
            Projection.expr (Person.id person)));
      let person = Option.value_exn !escaped in
      let values =
        Values.create
          ~table:Values_source.table
          ~columns:Values_source.columns
          ~first:
            (Values.Row.pair (Person.id person) (Expr.constant Db_type.text "outside"))
          ~rest:[]
      in
      let query =
        Query.(
          from_values values |> select (fun selected -> Values_source.columns selected))
      in
      match Compiler.compile_portable ~dialect:Dialect.Sqlite query with
      | Error (Compile_error.Foreign_source _) -> ()
      | _ -> failwith "VALUES row with an outer source reference was accepted"
    ;;
  end)
;;

let%expect_test "relation fields infer descriptors and stable SQL names" =
  Query.(
    from_relation inferred_active_people
    |> where (fun (id, _name) -> id >$ 10L)
    |> select (fun (id, name) -> Projection.pair id name))
  |> compile_portable_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."field_1",
      t0."field_2"
    FROM (
      SELECT
        t1."id" AS "field_1",
        t1."name" AS "field_2"
      FROM "public"."people" AS t1
      WHERE
        (t1."name" = $1)
    ) AS t0
    WHERE
      (t0."field_1" > $2)
    |}]
;;

let%test_unit "inferred relation fields can be inner- and left-joined" =
  let inner =
    Query.(
      from Person.table
      |> inner_join_relation inferred_active_people ~on:(fun person (id, _name) ->
        Person.id person =. id)
      |> select (fun (person, (_id, name)) -> Projection.pair (Person.name person) name))
  in
  let left =
    Query.(
      from Person.table
      |> left_join_relation inferred_active_people ~on:(fun person (id, _name) ->
        Person.id person =. id)
      |> select (fun (person, (_id, name)) -> Projection.pair (Person.name person) name))
  in
  let inner_sql = inner |> compile_portable_exn Dialect.Sqlite |> Compiled_query.sql in
  let left_sql = left |> compile_portable_exn Dialect.Postgresql |> Compiled_query.sql in
  assert (String.is_substring inner_sql ~substring:"INNER JOIN (");
  assert (String.is_substring left_sql ~substring:"LEFT JOIN (")
;;

let%expect_test "derived tables preserve relation columns and parameter order" =
  let query =
    Query.(
      from_derived active_people
      |> where (fun person -> Selected_person.id person >$ 10L)
      |> select Selected_person.projection)
  in
  query
  |> compile_portable_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."id",
      t0."name"
    FROM (
      SELECT
        t1."id" AS "id",
        t1."name" AS "name"
      FROM "public"."people" AS t1
      WHERE
        (t1."name" = $1)
    ) AS t0
    WHERE
      (t0."id" > $2)
    |}]
;;

let%test_unit "derived tables can be inner- and left-joined" =
  let inner =
    Query.(
      from Person.table
      |> inner_join_derived active_people ~on:(fun person selected ->
        Person.id person =. Selected_person.id selected)
      |> select (fun (person, selected) ->
        Projection.pair (Person.name person) (Selected_person.name selected)))
  in
  let left =
    Query.(
      from Person.table
      |> left_join_derived active_people ~on:(fun person selected ->
        Person.id person =. Selected_person.id selected)
      |> select (fun (person, selected) ->
        Projection.pair (Person.name person) (Selected_person.nullable_name selected)))
  in
  let inner_sql = inner |> compile_portable_exn Dialect.Sqlite |> Compiled_query.sql in
  let left_sql = left |> compile_portable_exn Dialect.Postgresql |> Compiled_query.sql in
  assert (String.is_substring inner_sql ~substring:"INNER JOIN (");
  assert (String.is_substring left_sql ~substring:"LEFT JOIN (")
;;

let first_branch =
  Query.(
    from Person.table
    |> where (fun person -> Person.id person >$ 10L)
    |> order_by Person.id `Desc
    |> limit 2
    |> select Person.projection)
;;

let second_branch =
  Query.(
    from Person.table
    |> where (fun person -> Person.id person <$ 5L)
    |> order_by Person.id `Asc
    |> limit 3
    |> select Person.projection)
;;

let%expect_test "UNION ALL wraps branches with local ordering and limits" =
  Query.union_all first_branch second_branch
  |> compile_portable_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    SELECT *
    FROM (
      SELECT
        t0."id",
        t0."name"
      FROM "public"."people" AS t0
      WHERE
        (t0."id" > ?1)
      ORDER BY
        t0."id" DESC
      LIMIT 2
    ) AS s0
    UNION ALL
    SELECT *
    FROM (
      SELECT
        t0."id",
        t0."name"
      FROM "public"."people" AS t0
      WHERE
        (t0."id" < ?2)
      ORDER BY
        t0."id" ASC
      LIMIT 3
    ) AS s0
    |}]
;;

let%test_unit "UNION, INTERSECT, and EXCEPT remain portable" =
  let queries =
    [ Query.union first_branch second_branch
    ; Query.intersect first_branch second_branch
    ; Query.except first_branch second_branch
    ]
  in
  List.iter queries ~f:(fun query ->
    let postgres =
      query |> compile_portable_exn Dialect.Postgresql |> Compiled_query.sql
    in
    let sqlite = query |> compile_portable_exn Dialect.Sqlite |> Compiled_query.sql in
    assert (String.is_substring postgres ~substring:"SELECT *");
    assert (String.is_substring sqlite ~substring:"SELECT *"))
;;

let%test_unit "PostgreSQL exposes duplicate-preserving set operations" =
  let intersect_all =
    Postgresql.Query.intersect_all first_branch second_branch
    |> compile_dialect_exn Dialect.postgresql
    |> Compiled_query.sql
  in
  let except_all =
    Postgresql.Query.except_all first_branch second_branch
    |> compile_dialect_exn Dialect.postgresql
    |> Compiled_query.sql
  in
  assert (String.is_substring intersect_all ~substring:"INTERSECT ALL");
  assert (String.is_substring except_all ~substring:"EXCEPT ALL")
;;

let%expect_test "set operations reject different database-type vectors" =
  let alternate_int64 =
    Db_type.map
      ~name:"alternate-int64"
      ~encode:Result.return
      ~decode:Result.return
      Db_type.int64
  in
  let right =
    Query.(
      from Person.table
      |> select (fun _ -> Projection.expr (Expr.constant alternate_int64 1L)))
  in
  ( Query.union
      Query.(
        from Person.table |> select (fun person -> Projection.expr (Person.id person)))
      right
    |> Compiler.compile_portable ~dialect:Dialect.Postgresql
  |> function
    | Ok _ -> failwith "set operation unexpectedly accepted different codecs"
    | Error error -> Stdlib.print_endline (Compile_error.to_string error) );
  [%expect {| set operation left types [int64] do not match right types [map#0(int64)] |}]
;;

let%test_unit "derived relation descriptors are validated before rendering" =
  let compile relation =
    Query.(
      from_derived relation
      |> select (fun number -> Projection.expr (Number.value number)))
    |> Compiler.compile_portable ~dialect:Dialect.Sqlite
  in
  let invalid_column =
    Derived_table.create
      ~table:Number.table
      ~columns:(fun _ -> Projection.expr (Expr.constant Db_type.int64 0L))
      Query.(
        from Person.table |> select (fun person -> Projection.expr (Person.id person)))
  in
  (match compile invalid_column with
   | Error (Compile_error.Invalid_relation_column 1 as error) ->
     assert (
       String.equal
         (Compile_error.to_string error)
         "relation output #1 must be a direct descriptor column")
   | _ -> failwith "non-column relation descriptor was accepted");
  let duplicate_columns =
    Derived_table.create
      ~table:Selected_person.table
      ~columns:(fun selected ->
        Projection.pair (Selected_person.id selected) (Selected_person.id selected))
      Query.(
        from Person.table
        |> select (fun person -> Projection.pair (Person.id person) (Person.id person)))
  in
  let duplicate_query =
    Query.(
      from_derived duplicate_columns
      |> select (fun selected -> Projection.expr (Selected_person.id selected)))
  in
  (match Compiler.compile_portable ~dialect:Dialect.Sqlite duplicate_query with
   | Error (Compile_error.Duplicate_relation_column _ as error) ->
     assert (
       String.equal
         (Compile_error.to_string error)
         "relation output column id occurs more than once")
   | _ -> failwith "duplicate relation descriptor was accepted");
  let mismatched_types =
    Derived_table.create
      ~table:Number.table
      ~columns:(fun number -> Projection.expr (Number.value number))
      Query.(
        from Person.table |> select (fun person -> Projection.expr (Person.name person)))
  in
  match compile mismatched_types with
  | Error (Compile_error.Mismatched_relation_projection _ as error) ->
    assert (
      String.equal
        (Compile_error.to_string error)
        "relation output types [int64] do not match SELECT types [text]")
  | _ -> failwith "mismatched relation descriptor was accepted"
;;

let%test_unit "new compile errors have stable public diagnostics" =
  let cases =
    [ ( Compile_error.Empty_conflict_target
      , "ON CONFLICT target must contain at least one column" )
    ; ( Compile_error.Unsupported_operation
          { operation = "INTERSECT ALL"; dialect = Dialect.Sqlite }
      , "INTERSECT ALL is not supported by the sqlite dialect" )
    ; Compile_error.Unknown_cte 7, "query references unavailable CTE #7"
    ]
  in
  List.iter cases ~f:(fun (error, expected) ->
    assert (String.equal (Compile_error.to_string error) expected))
;;

let materialized_people = Cte.select ~materialization:`Materialized active_people
let not_materialized_people = Cte.select ~materialization:`Not_materialized active_people

let%expect_test "materialized CTEs expose typed relations" =
  Cte.with_result materialized_people ~f:(fun people ->
    Query.(
      from_cte people
      |> where (fun person -> Selected_person.id person >$ 10L)
      |> select Selected_person.projection))
  |> compile_portable_exn Dialect.Postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    WITH
      "c0" (
        "id",
        "name"
      ) AS MATERIALIZED (
        SELECT
          t0."id",
          t0."name"
        FROM "public"."people" AS t0
        WHERE
          (t0."name" = $1)
      )
    SELECT
      t0."id",
      t0."name"
    FROM "c0" AS t0
    WHERE
      (t0."id" > $2)
    |}]
;;

let%test_unit "a CTE can supply UPDATE FROM" =
  let command =
    Cte.with_command materialized_people ~f:(fun people ->
      Update.(
        table Person.table
        |> from_cte people ~f:(fun person selected update ->
          update
          |> set_expr Person.name_column (Selected_person.name selected)
          |> where (fun _ -> Person.id person =. Selected_person.id selected))
        |> command))
  in
  let postgres =
    command |> Compiler.compile_portable_command ~dialect:Dialect.Postgresql
  in
  let sqlite = command |> Compiler.compile_portable_command ~dialect:Dialect.Sqlite in
  let sql = function
    | Ok compiled -> Compiled_command.sql compiled
    | Error error -> failwith (Compile_error.to_string error)
  in
  assert (String.is_substring (sql postgres) ~substring:"WITH");
  assert (String.is_substring (sql postgres) ~substring:"FROM \"c0\" AS t1");
  assert (String.is_substring (sql sqlite) ~substring:"FROM \"c0\" AS t1")
;;

let%test_unit "CTEs can be joined and multiple definitions retain lexical order" =
  let inner =
    Cte.with_result not_materialized_people ~f:(fun selected ->
      Query.(
        from Person.table
        |> inner_join_cte selected ~on:(fun person selected ->
          Person.id person =. Selected_person.id selected)
        |> select (fun (person, selected) ->
          Projection.pair (Person.name person) (Selected_person.name selected))))
  in
  let left =
    Cte.with_result not_materialized_people ~f:(fun selected ->
      Query.(
        from Person.table
        |> left_join_cte selected ~on:(fun person selected ->
          Person.id person =. Selected_person.id selected)
        |> select (fun (person, selected) ->
          Projection.pair (Person.name person) (Selected_person.nullable_name selected))))
  in
  let second = Cte.select active_people in
  let multiple =
    Cte.with_result not_materialized_people ~f:(fun first ->
      Cte.with_result second ~f:(fun second ->
        Query.(
          from_cte first
          |> inner_join_cte second ~on:(fun first second ->
            Selected_person.id first =. Selected_person.id second)
          |> select (fun (first, second) ->
            Projection.pair (Selected_person.name first) (Selected_person.name second)))))
  in
  let inner_sql = inner |> compile_portable_exn Dialect.Sqlite |> Compiled_query.sql in
  let left_sql = left |> compile_portable_exn Dialect.Sqlite |> Compiled_query.sql in
  let multiple_sql =
    multiple |> compile_portable_exn Dialect.Postgresql |> Compiled_query.sql
  in
  assert (String.is_substring inner_sql ~substring:"AS NOT MATERIALIZED");
  assert (String.is_substring inner_sql ~substring:"INNER JOIN \"c0\"");
  assert (String.is_substring left_sql ~substring:"LEFT JOIN \"c0\"");
  assert (String.is_substring multiple_sql ~substring:"\"c0\"");
  assert (String.is_substring multiple_sql ~substring:"\"c1\"")
;;

let%test_unit "a derived relation can supply UPDATE FROM" =
  let command =
    Update.(
      table Person.table
      |> from_derived active_people ~f:(fun person selected update ->
        update
        |> set_expr Person.name_column (Selected_person.name selected)
        |> where (fun _ -> Person.id person =. Selected_person.id selected))
      |> command)
  in
  let sql =
    command
    |> Compiler.compile_portable_command ~dialect:Dialect.Postgresql
    |> Result.map ~f:Compiled_command.sql
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
  in
  assert (String.is_substring sql ~substring:"FROM (")
;;

let%test_unit "an inferred relation can supply UPDATE FROM" =
  let command =
    Update.(
      table Person.table
      |> from_relation inferred_active_people ~f:(fun person (id, name) update ->
        update
        |> set_expr Person.name_column name
        |> where (fun _ -> Person.id person =. id))
      |> command)
  in
  let sql =
    command
    |> Compiler.compile_portable_command ~dialect:Dialect.Postgresql
    |> Result.map ~f:Compiled_command.sql
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
  in
  assert (String.is_substring sql ~substring:"FROM (");
  assert (String.is_substring sql ~substring:"t1.\"field_2\"")
;;

let%test_unit "multiple UPDATE FROM sources preserve their append order" =
  let command =
    Update.(
      table Person.table
      |> from Person.table ~f:(fun person first update ->
        update
        |> from Person.table ~f:(fun _ second update ->
          update
          |> set_expr Person.name_column (Person.name second)
          |> where (fun _ -> Person.id person =. Person.id first)))
      |> command)
  in
  let sql =
    command
    |> Compiler.compile_portable_command ~dialect:Dialect.Sqlite
    |> Result.map ~f:Compiled_command.sql
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
  in
  assert (String.count sql ~f:(Char.equal ',') >= 1)
;;

let%test_unit "CTEs attach to compound SELECTs and RETURNING statements" =
  let compound =
    Cte.with_result not_materialized_people ~f:(fun _ ->
      Query.union first_branch second_branch)
  in
  let returning =
    Cte.with_result not_materialized_people ~f:(fun _ ->
      Insert.(
        into Person.table
        |> default Person.id_column
        |> set Person.name_column "Ada"
        |> returning Person.projection))
  in
  let compound_sql =
    compound |> compile_portable_exn Dialect.Sqlite |> Compiled_query.sql
  in
  let returning_sql =
    returning |> compile_dialect_exn Dialect.postgresql |> Compiled_query.sql
  in
  assert (String.is_prefix compound_sql ~prefix:"WITH");
  assert (String.is_prefix returning_sql ~prefix:"WITH")
;;

let inserted_people =
  Postgresql.Cte.returning
    ~table:Selected_person.table
    ~columns:Selected_person.projection
    Insert.(
      into Person.table
      |> default Person.id_column
      |> set Person.name_column "Ada"
      |> returning Person.projection)
;;

let%expect_test "PostgreSQL data-modifying CTEs can feed a SELECT" =
  Cte.with_result inserted_people ~f:(fun people ->
    Query.(from_cte people |> select Selected_person.projection))
  |> compile_dialect_exn Dialect.postgresql
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    WITH
      "c0" (
        "id",
        "name"
      ) AS (
        INSERT INTO "public"."people" (
          "id",
          "name"
        )
        VALUES
          (DEFAULT, $1)
        RETURNING
          "id",
          "name"
      )
    SELECT
      t0."id",
      t0."name"
    FROM "c0" AS t0
    |}]
;;

let command_effect =
  Postgresql.Cte.command
    Update.(table Person.table |> default Person.name_column |> all_rows |> command)
;;

let%expect_test "PostgreSQL data-modifying CTE commands precede outer DML" =
  Cte.with_command command_effect ~f:(fun () ->
    Insert.(
      into Person.table
      |> default Person.id_column
      |> set Person.name_column "Grace"
      |> command))
  |> compile_dialect_command_exn Dialect.postgresql
  |> Compiled_command.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    WITH
      "c0" AS (
        UPDATE "public"."people"
        SET
          "name" = DEFAULT
      )
    INSERT INTO "public"."people" (
      "id",
      "name"
    )
    VALUES
      (DEFAULT, $1)
    |}]
;;

let numbers_relation query =
  Derived_table.create
    ~table:Number.table
    ~columns:(fun number -> Projection.expr (Number.value number))
    query
;;

let recursive_numbers =
  Cte.recursive
    ~union:`Union_all
    ~anchor:
      (numbers_relation
         Query.(
           from Person.table
           |> where (fun person -> Person.id person <=$ 3L)
           |> select (fun person -> Projection.expr (Person.id person))))
    ~step:(fun numbers ->
      numbers_relation
        Query.(
          from_cte numbers
          |> where (fun number -> Number.value number <$ 5L)
          |> select (fun number ->
            let open Expr.Int64.Infix in
            Projection.expr (Number.value number +. Expr.constant Db_type.int64 1L))))
;;

let recursive_distinct_numbers =
  Cte.recursive
    ~union:`Union
    ~anchor:
      (numbers_relation
         Query.(
           from Person.table
           |> where (fun person -> Person.id person <=$ 3L)
           |> select (fun person -> Projection.expr (Person.id person))))
    ~step:(fun numbers ->
      numbers_relation
        Query.(
          from_cte numbers
          |> where (fun number -> Number.value number <$ 5L)
          |> select (fun number -> Projection.expr (Number.value number))))
;;

let compile_recursive definition =
  Cte.with_result definition ~f:(fun numbers ->
    Query.(
      from_cte numbers |> select (fun number -> Projection.expr (Number.value number))))
  |> Compiler.compile_portable ~dialect:Dialect.Sqlite
;;

let%test_unit "recursive CTE validation rejects missing, duplicate, and compound self use"
  =
  let anchor =
    numbers_relation
      Query.(
        from Person.table |> select (fun person -> Projection.expr (Person.id person)))
  in
  let missing = Cte.recursive ~union:`Union_all ~anchor ~step:(fun _ -> anchor) in
  let duplicate =
    Cte.recursive ~union:`Union_all ~anchor ~step:(fun numbers ->
      numbers_relation
        Query.(
          from_cte numbers
          |> inner_join_cte numbers ~on:(fun left right ->
            Number.value left =. Number.value right)
          |> select (fun (left, _) -> Projection.expr (Number.value left))))
  in
  let compound =
    Cte.recursive ~union:`Union_all ~anchor ~step:(fun numbers ->
      let self =
        Query.(
          from_cte numbers |> select (fun number -> Projection.expr (Number.value number)))
      in
      let other =
        Query.(
          from Person.table |> select (fun person -> Projection.expr (Person.id person)))
      in
      numbers_relation (Query.union self other))
  in
  let nested =
    Cte.recursive ~union:`Union_all ~anchor ~step:(fun numbers ->
      let nested_self =
        numbers_relation
          Query.(
            from_cte numbers
            |> select (fun number -> Projection.expr (Number.value number)))
      in
      numbers_relation
        Query.(
          from_cte numbers
          |> inner_join_derived nested_self ~on:(fun direct nested ->
            Number.value direct =. Number.value nested)
          |> select (fun (direct, _) -> Projection.expr (Number.value direct))))
  in
  List.iter [ missing; duplicate; compound; nested ] ~f:(fun definition ->
    match compile_recursive definition with
    | Error (Compile_error.Invalid_recursive_reference _ as error) ->
      assert (String.is_substring (Compile_error.to_string error) ~substring:"recursive")
    | _ -> failwith "invalid recursive CTE was accepted")
;;

let%test_unit "recursive CTE validation checks step types and nested subqueries" =
  let anchor =
    numbers_relation
      Query.(
        from Person.table |> select (fun person -> Projection.expr (Person.id person)))
  in
  let alternate_int64 =
    Db_type.map
      ~name:"recursive-int64"
      ~encode:Result.return
      ~decode:Result.return
      Db_type.int64
  in
  let alternate_table : Number.row Table.t = Table.v_exn "alternate_numbers" in
  let alternate_column = Column.v_exn alternate_table "value" alternate_int64 in
  let mismatched =
    Cte.recursive ~union:`Union_all ~anchor ~step:(fun numbers ->
      Derived_table.create
        ~table:alternate_table
        ~columns:(fun row -> Projection.expr (Expr.column row alternate_column))
        Query.(
          from_cte numbers
          |> select (fun _ -> Projection.expr (Expr.constant alternate_int64 1L))))
  in
  (match compile_recursive mismatched with
   | Error (Compile_error.Mismatched_set_projection _) -> ()
   | _ -> failwith "recursive CTE accepted incompatible step types");
  let counted =
    Query.(
      from Person.table |> select_scalar (fun person -> Expr.count (Person.id person)))
  in
  let nested =
    Cte.recursive ~union:`Union_all ~anchor ~step:(fun numbers ->
      numbers_relation
        Query.(
          from_cte numbers
          |> where (fun _ -> Expr.is_not_null (Expr.scalar_subquery counted))
          |> select (fun number -> Projection.expr (Number.value number))))
  in
  ignore
    (compile_recursive nested
     |> Result.map_error ~f:Compile_error.to_string
     |> Result.ok_or_failwith)
;;

let%test_unit "scalar cardinality inspects parameter-only projections" =
  let scalar =
    Query.(from Person.table |> select_scalar (fun _ -> Expr.constant Db_type.int64 1L))
  in
  let outer =
    Query.(
      from Person.table |> select (fun _ -> Projection.expr (Expr.scalar_subquery scalar)))
  in
  match Compiler.compile_portable ~dialect:Dialect.Sqlite outer with
  | Error Compile_error.Scalar_subquery_may_return_many_rows -> ()
  | _ -> failwith "unbounded scalar subquery was accepted"
;;

let%test_unit "duplicate UPDATE assignments remain compile errors" =
  let command =
    Update.(
      table Person.table
      |> set Person.name_column "Ada"
      |> set Person.name_column "Grace"
      |> all_rows
      |> command)
  in
  match Compiler.compile_portable_command ~dialect:Dialect.Sqlite command with
  | Error (Compile_error.Duplicate_assignment _) -> ()
  | _ -> failwith "duplicate UPDATE assignment was accepted"
;;

let%expect_test "recursive CTEs render their typed self-reference" =
  Cte.with_result recursive_numbers ~f:(fun numbers ->
    Query.(
      from_cte numbers |> select (fun number -> Projection.expr (Number.value number))))
  |> compile_portable_exn Dialect.Sqlite
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    WITH RECURSIVE
      "c0" (
        "value"
      ) AS (
        SELECT
          t0."id"
        FROM "public"."people" AS t0
        WHERE
          (t0."id" <= ?1)
        UNION ALL
        SELECT
          (t0."value" + ?2)
        FROM "c0" AS t0
        WHERE
          (t0."value" < ?3)
      )
    SELECT
      t0."value"
    FROM "c0" AS t0
    |}]
;;

let%test_unit "recursive CTEs support duplicate-eliminating UNION" =
  let sql =
    Cte.with_result recursive_distinct_numbers ~f:(fun numbers ->
      Query.(
        from_cte numbers |> select (fun number -> Projection.expr (Number.value number))))
    |> compile_portable_exn Dialect.Sqlite
    |> Compiled_query.sql
  in
  assert (String.is_substring sql ~substring:"\n    UNION\n")
;;

let%test_unit "compiled relation queries support public formatting" =
  let compiled = compile_portable_exn Dialect.Sqlite first_branch in
  let rendered = Stdlib.Format.asprintf "%a" Compiled_query.pp compiled in
  assert (String.equal rendered (Compiled_query.sql compiled))
;;
