open! Base
open Typed_sql
module Raw = Raw_sql.Postgresql

let id = Identifier.of_string_exn "id"
let output = Raw_sql.Output.field ~name:id Db_type.int
let select parts = Raw.select ~output parts

let sql query =
  Statement.query_many ~dialect:Dialect.postgresql query
  |> Statement.sql_exn ~dialect:Postgresql
;;

module Row = struct
  type t

  let table : t Table.t = Table.v_exn "raw_rows"
  let column = Column.v_exn table "id" Db_type.int
  let projection row = Projection.expr (Expr.column row column)
end

let relation query = Derived_table.create ~table:Row.table ~columns:Row.projection query
let from_relation relation = Query.(from_derived relation |> select Row.projection)

let%test_module "raw templates and parameters" =
  (module struct
    let repeated_parameter_statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let%map.Parameters value = params.expr Db_type.int ~get:Fn.id in
        params.query_many
          (select
             [ Raw.unsafe_sql "SELECT "
             ; Raw.bind Db_type.int value
             ; Raw.unsafe_sql " + "
             ; Raw.bind Db_type.int value
             ]))
    ;;

    let nullable_parameter_statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let%map.Parameters parameter = params.optional_expr Db_type.int ~get:Fn.id in
        params.query_many
          (Raw.select
             ~output:(Raw_sql.Output.field ~name:id (Db_type.option Db_type.int))
             [ Raw.unsafe_sql "SELECT "
             ; Raw.bind
                 (Db_type.option Db_type.int)
                 (Optional_parameter.nullable_expr parameter)
             ]))
    ;;

    let%expect_test "raw text and values remain separate" =
      sql
        (select
           [ Raw.unsafe_sql "SELECT "
           ; Raw.bind Db_type.int (Expr.constant Db_type.int 42)
           ])
      |> Stdlib.print_endline;
      [%expect {| SELECT $1 |}]
    ;;

    let%expect_test "raw returning is a row result" =
      sql (Raw.returning ~output [ Raw.unsafe_sql "DELETE FROM people RETURNING id" ])
      |> Stdlib.print_endline;
      [%expect {| DELETE FROM people RETURNING id |}]
    ;;

    let%expect_test "raw commands use the command compiler" =
      Statement.command
        ~dialect:Dialect.postgresql
        (Raw.command [ Raw.unsafe_sql "DELETE FROM people" ])
      |> Statement.sql_exn ~dialect:Postgresql
      |> Stdlib.print_endline;
      [%expect {| DELETE FROM people |}]
    ;;

    let%test_unit "raw SQL works with reusable statement inputs" =
      let first_sql, first =
        Statement.inspect_exn ~dialect:Postgresql ~input:3 repeated_parameter_statement
      in
      let second_sql, second =
        Statement.inspect_exn ~dialect:Postgresql ~input:4 repeated_parameter_statement
      in
      assert (String.equal first_sql second_sql);
      List.iter2_exn [ first; second ] [ "3"; "4" ] ~f:(fun inspection expected ->
        match inspection.Statement.parameters with
        | [ { value = Some (Encoded actual); _ } ] ->
          assert (String.equal actual expected)
        | _ -> failwith "expected one bound raw parameter")
    ;;

    let%expect_test "repeated raw holes share one inspected parameter" =
      let sql, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:3 repeated_parameter_statement
      in
      Stdlib.print_endline sql;
      [%expect {| SELECT $1 + $1 |}];
      Statement.sexp_of_inspection inspection
      |> Sexp.to_string_hum
      |> Stdlib.print_endline;
      [%expect
        {|
        ((dialect Postgresql)
         (parameters
          (((position 1) (placeholder $1) (name ()) (db_type int)
            (dialect_type (integer)) (value ((Encoded 3))))))
         (output
          (Query_output (cardinality Many)
           (columns
            (((position 1) (name (id)) (db_type int) (dialect_type (integer)))))))
         (tree (Leaf (kind Query) (mode Static))))
        |}]
    ;;

    let%expect_test "bind positions follow SQL order across raw and DSL" =
      let statement =
        Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
          let%map.Parameters first = params.expr ~name:"first" Db_type.int ~get:fst
          and second = params.expr ~name:"second" Db_type.int ~get:snd in
          let raw =
            select
              [ Raw.unsafe_sql "SELECT "
              ; Raw.bind Db_type.int second
              ; Raw.unsafe_sql " AS id WHERE "
              ; Raw.bind Db_type.int second
              ; Raw.unsafe_sql " > "
              ; Raw.bind Db_type.int first
              ]
          in
          let dsl = Query.(from Row.table |> select (fun _ -> Projection.expr first)) in
          params.query_many (Query.union_all raw dsl))
      in
      let sql, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:(3, 7) statement
      in
      Stdlib.print_endline sql;
      [%expect
        {|
        SELECT *
        FROM (
          SELECT $1 AS id WHERE $1 > $2
        ) AS s0
        UNION ALL
        SELECT *
        FROM (
          SELECT
            $2
          FROM "raw_rows" AS t0
        ) AS s0
        |}];
      List.iter inspection.parameters ~f:(fun parameter ->
        Statement.sexp_of_parameter parameter
        |> Sexp.to_string_hum
        |> Stdlib.print_endline);
      [%expect
        {|
        ((position 1) (placeholder $1) (name (second)) (db_type int)
         (dialect_type (integer)) (value ((Encoded 7))))
        ((position 2) (placeholder $2) (name (first)) (db_type int)
         (dialect_type (integer)) (value ((Encoded 3))))
        |}]
    ;;

    let%test_unit "input getters run on binding and the builder runs once" =
      let builds = ref 0 in
      let reads = ref 0 in
      let statement =
        Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
          Int.incr builds;
          let%map.Parameters id =
            params.expr Db_type.int ~get:(fun value ->
              Int.incr reads;
              value)
          in
          params.query_many (select [ Raw.unsafe_sql "SELECT "; Raw.bind Db_type.int id ]))
      in
      assert (Int.equal !builds 1);
      assert (Int.equal !reads 0);
      ignore (Statement.sql_exn ~dialect:Postgresql ~input:1 statement : string);
      ignore (Statement.sql_exn ~dialect:Postgresql ~input:2 statement : string);
      assert (Int.equal !builds 1);
      assert (Int.equal !reads 2)
    ;;

    let%test_unit "foreign raw slots report binding and inspection errors" =
      let captured = ref None in
      let _first =
        Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
          let%map.Parameters value = params.expr Db_type.int ~get:Fn.id in
          captured := Some value;
          params.query_many
            (select [ Raw.unsafe_sql "SELECT "; Raw.bind Db_type.int value ]))
      in
      let query =
        select
          [ Raw.unsafe_sql "SELECT "; Raw.bind Db_type.int (Option.value_exn !captured) ]
      in
      let statement = Statement.query_many ~dialect:Dialect.postgresql query in
      assert (Result.is_error (Statement.sql ~dialect:Postgresql ~input:() statement));
      assert (Result.is_error (Statement.inspect ~dialect:Postgresql statement))
    ;;

    let%test_unit "nullable optional parameter views remain bind slots" =
      assert (
        String.equal
          (Statement.sql_exn ~dialect:Postgresql ~input:None nullable_parameter_statement)
          "SELECT $1");
      assert (
        String.equal
          (Statement.sql_exn
             ~dialect:Postgresql
             ~input:(Some 1)
             nullable_parameter_statement)
          "SELECT $1")
    ;;

    let%expect_test "nullable raw bind inspection retains SQL NULL" =
      let _, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:None nullable_parameter_statement
      in
      Statement.sexp_of_inspection inspection
      |> Sexp.to_string_hum
      |> Stdlib.print_endline;
      [%expect
        {|
        ((dialect Postgresql)
         (parameters
          (((position 1) (placeholder $1) (name ()) (db_type "option(int)")
            (dialect_type (integer)) (value (Null)))))
         (output
          (Query_output (cardinality Many)
           (columns
            (((position 1) (name (id)) (db_type "option(int)")
              (dialect_type (integer)))))))
         (tree (Leaf (kind Query) (mode Static))))
        |}]
    ;;

    let%expect_test "debug SQL terminates after a trailing line comment" =
      let statement =
        Statement.query_many
          ~dialect:Dialect.postgresql
          (select [ Raw.unsafe_sql "SELECT 1 AS id -- trailing comment" ])
      in
      Statement.debug_sql_exn ~dialect:Postgresql ~input:() statement
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT 1 AS id -- trailing comment
        ;
        |}]
    ;;
  end)
;;

let%test_module "raw SQL diagnostics" =
  (module struct
    let print_definition_error create =
      match create () with
      | exception Statement.Definition_error error ->
        Statement.sexp_of_definition_error error
        |> Sexp.to_string_hum
        |> Stdlib.print_endline
      | _ -> failwith "expected raw statement definition error"
    ;;

    let print_query_error query =
      print_definition_error (fun () ->
        Statement.query_many ~dialect:Dialect.postgresql query)
    ;;

    let%expect_test "empty row decoders are rejected" =
      print_query_error
        (Raw.select ~output:(Raw_sql.Output.return ()) [ Raw.unsafe_sql "SELECT 1" ]);
      [%expect
        {|
        ((dialect Postgresql) (error Empty_projection))
        |}]
    ;;

    let%expect_test "blank templates are rejected" =
      print_query_error (select [ Raw.unsafe_sql "  " ]);
      [%expect
        {|
        ((dialect Postgresql) (error (Invalid_raw_sql "empty SQL template")))
        |}]
    ;;

    let%expect_test "computed placeholders are rejected" =
      let open Expr.Int.Infix in
      print_query_error
        (select
           [ Raw.unsafe_sql "SELECT "
           ; Raw.bind
               Db_type.int
               (Expr.constant Db_type.int 1 +. Expr.constant Db_type.int 2)
           ]);
      [%expect
        {|
        ((dialect Postgresql)
         (error
          (Invalid_raw_sql
           "only bind parameters and constants are supported in raw holes")))
        |}]
    ;;

    let%expect_test "descriptors must match even when OCaml types agree" =
      let named =
        Db_type.Postgresql.named
          ~schema:(Identifier.of_string_exn "public")
          ~name:(Identifier.of_string_exn "tag")
          Db_type.int
      in
      print_query_error
        (select
           [ Raw.unsafe_sql "SELECT "; Raw.bind named (Expr.constant Db_type.int 1) ]);
      [%expect
        {|
        ((dialect Postgresql)
         (error
          (Mismatched_sql_type (context "raw bind") (expected "\"public\".\"tag\"")
           (actual integer))))
        |}]
    ;;

    let%expect_test "restricted raw selects cannot be nested" =
      let query =
        Raw.select
          ~top_level_only:true
          ~output
          [ Raw.unsafe_sql "SELECT id FROM people FOR UPDATE" ]
      in
      print_query_error (from_relation (relation query));
      [%expect
        {|
        ((dialect Postgresql) (error Invalid_cte_placement))
        |}]
    ;;

    let%expect_test "raw RETURNING rejects attaching DSL CTEs" =
      let definition =
        Cte.select (relation (select [ Raw.unsafe_sql "SELECT 1 AS id" ]))
      in
      print_query_error
        (Cte.with_result definition ~f:(fun _ ->
           Raw.returning ~output [ Raw.unsafe_sql "DELETE FROM people RETURNING id" ]));
      [%expect
        {|
        ((dialect Postgresql)
         (error
          (Invalid_raw_sql
           "cannot attach DSL CTEs to a top-level-only raw statement")))
        |}]
    ;;

    let%expect_test "raw commands reject attaching DSL CTEs" =
      let definition =
        Cte.select (relation (select [ Raw.unsafe_sql "SELECT 1 AS id" ]))
      in
      let command =
        Cte.with_command definition ~f:(fun _ ->
          Raw.command [ Raw.unsafe_sql "DELETE FROM people" ])
      in
      print_definition_error (fun () ->
        Statement.command ~dialect:Dialect.postgresql command);
      [%expect
        {|
        ((dialect Postgresql)
         (error
          (Invalid_raw_sql
           "cannot attach DSL CTEs to a top-level-only raw statement")))
        |}]
    ;;

    let%expect_test "a bind alone is not a SQL statement" =
      print_query_error (select [ Raw.bind Db_type.int (Expr.constant Db_type.int 1) ]);
      [%expect
        {|
        ((dialect Postgresql) (error (Invalid_raw_sql "empty SQL template")))
        |}]
    ;;

    let%test "raw recursive steps cannot claim a checked self-reference" =
      let definition =
        Cte.recursive
          ~union:`Union_all
          ~anchor:(relation (select [ Raw.unsafe_sql "SELECT 1 AS id" ]))
          ~step:(fun _ -> relation (select [ Raw.unsafe_sql "SELECT 2 AS id" ]))
      in
      let query =
        Cte.with_result definition ~f:(fun cte ->
          Query.(from_cte cte |> select Row.projection))
      in
      match Statement.query_many ~dialect:Dialect.postgresql query with
      | exception Statement.Definition_error { error = Invalid_recursive_reference _; _ }
        -> true
      | _ -> false
    ;;

    let%expect_test "optional parameter value view cannot disguise a nullable raw slot" =
      print_definition_error (fun () ->
        Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
          let%map.Parameters parameter = params.optional_expr Db_type.int ~get:Fn.id in
          let captured = ref None in
          let _guarded =
            Query.(
              from Row.table
              |> where_optional_param parameter ~f:(fun _ value ->
                captured := Some value;
                Condition.true_))
          in
          params.query_many
            (select
               [ Raw.unsafe_sql "SELECT "
               ; Raw.bind Db_type.int (Option.value_exn !captured)
               ])));
      [%expect
        {|
        ((dialect Postgresql)
         (error (Invalid_raw_sql "raw bind nullable representation mismatch")))
        |}]
    ;;
  end)
;;

let%test_module "raw relational composition" =
  (module struct
    let%expect_test "raw selects compose with derived tables" =
      sql (from_relation (relation (select [ Raw.unsafe_sql "SELECT 1 AS id" ])))
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id"
        FROM (
          SELECT "__typed_sql_raw"."c0" AS "id" FROM (
        SELECT 1 AS id
        ) AS "__typed_sql_raw" ("c0")
        ) AS t0
        |}]
    ;;

    let%expect_test "raw selects compose with CTEs" =
      let cte = Cte.select (relation (select [ Raw.unsafe_sql "SELECT 1 AS id" ])) in
      let query =
        Cte.with_result cte ~f:(fun cte -> Query.(from_cte cte |> select Row.projection))
      in
      sql query |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" (
            "id"
          ) AS (
            SELECT 1 AS id
          )
        SELECT
          t0."id"
        FROM "c0" AS t0
        |}]
    ;;

    let%expect_test "UNION ALL composes raw and DSL selects" =
      let raw = select [ Raw.unsafe_sql "SELECT 1 AS id" ] in
      let dsl = Query.(from Row.table |> select Row.projection) in
      sql (Query.union_all raw dsl) |> Stdlib.print_endline;
      [%expect
        {|
        SELECT *
        FROM (
          SELECT 1 AS id
        ) AS s0
        UNION ALL
        SELECT *
        FROM (
          SELECT
            t0."id"
          FROM "raw_rows" AS t0
        ) AS s0
        |}]
    ;;

    let%expect_test "a DSL CTE can be attached to a nestable raw SELECT" =
      let definition =
        Cte.select (relation (select [ Raw.unsafe_sql "SELECT 1 AS id" ]))
      in
      let query =
        Cte.with_result definition ~f:(fun _ ->
          select [ Raw.unsafe_sql "SELECT 2 AS id" ])
      in
      sql query |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" (
            "id"
          ) AS (
            SELECT 1 AS id
          )
        SELECT "__typed_sql_raw"."c0" AS "id" FROM (
        SELECT 2 AS id
        ) AS "__typed_sql_raw" ("c0")
        |}]
    ;;

    let%expect_test "raw RETURNING can define a DML CTE" =
      let definition =
        Postgresql.Cte.returning
          ~table:Row.table
          ~columns:Row.projection
          (Raw.returning ~output [ Raw.unsafe_sql "DELETE FROM people RETURNING id" ])
      in
      let query =
        Cte.with_result definition ~f:(fun cte ->
          Query.(from_cte cte |> select Row.projection))
      in
      sql query |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" (
            "id"
          ) AS (
            DELETE FROM people RETURNING id
          )
        SELECT
          t0."id"
        FROM "c0" AS t0
        |}]
    ;;

    let%expect_test "raw commands can define effect-only CTEs" =
      let definition =
        Postgresql.Cte.command (Raw.command [ Raw.unsafe_sql "DELETE FROM people" ])
      in
      let query =
        Cte.with_result definition ~f:(fun () ->
          Query.(from Row.table |> select Row.projection))
      in
      sql query |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" AS (
            DELETE FROM people
          )
        SELECT
          t0."id"
        FROM "raw_rows" AS t0
        |}]
    ;;

    let%expect_test "raw rows participate in nested multiset decoding" =
      let nested = select [ Raw.unsafe_sql "SELECT 1 AS id" ] in
      let query = Query.(from Row.table |> select (fun _ -> multiset nested)) in
      sql query |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          CAST(
            (
              SELECT
                COALESCE(
                  JSONB_AGG(
                    JSONB_BUILD_ARRAY(
                      m0."v0"
                    )
                  ),
                  JSONB_BUILD_ARRAY()
                )
              FROM LATERAL (
                SELECT "__typed_sql_raw"."c0" AS "v0" FROM (
        SELECT 1 AS id
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "raw_rows" AS t0
        |}]
    ;;

    let%expect_test "ordered set operations address raw output names" =
      let left = select [ Raw.unsafe_sql "SELECT 1 AS id" ] in
      let right = select [ Raw.unsafe_sql "SELECT 2 AS id" ] in
      sql (Query.union_all ~order_by:[ id, `Asc ] left right) |> Stdlib.print_endline;
      [%expect
        {|
        SELECT *
        FROM (
          SELECT 1 AS id
        ) AS s0
        UNION ALL
        SELECT *
        FROM (
          SELECT 2 AS id
        ) AS s0
        ORDER BY
          "id" ASC
        |}]
    ;;

    let%expect_test "ordered UNION outputs retain positional aliases inside multisets" =
      let left = select [ Raw.unsafe_sql "SELECT 1 AS id" ] in
      let right = select [ Raw.unsafe_sql "SELECT 2 AS id" ] in
      let combined = Query.union_all ~order_by:[ id, `Asc ] left right in
      let query = Query.(from Row.table |> select (fun _ -> multiset combined)) in
      sql query |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          CAST(
            (
              SELECT
                COALESCE(
                  JSONB_AGG(
                    JSONB_BUILD_ARRAY(
                      m0."v0"
                    )
                  ),
                  JSONB_BUILD_ARRAY()
                )
              FROM LATERAL (
                SELECT *
                FROM LATERAL (
                  SELECT "__typed_sql_raw"."c0" AS "v0" FROM (
        SELECT 1 AS id
        ) AS "__typed_sql_raw" ("c0")
                ) AS s0
                UNION ALL
                SELECT *
                FROM LATERAL (
                  SELECT "__typed_sql_raw"."c0" AS "v0" FROM (
        SELECT 2 AS id
        ) AS "__typed_sql_raw" ("c0")
                ) AS s0
                ORDER BY
                  "v0" ASC
              ) AS m0
            )
            AS TEXT
          )
        FROM "raw_rows" AS t0
        |}]
    ;;
  end)
;;

let%test_module "raw CTEs in DSL commands" =
  (module struct
    let merge_command () =
      let open Infix in
      Merge.(
        into Row.table
        |> using Row.table ~f:(fun target source merge ->
          merge
          |> on (Expr.column target Row.column =. Expr.column source Row.column)
          |> when_matched_delete)
        |> command)
    ;;

    let%expect_test "raw effect-only CTEs compose with a DSL MERGE" =
      let definition =
        Postgresql.Cte.command (Raw.command [ Raw.unsafe_sql "DELETE FROM people" ])
      in
      let command = Cte.with_command definition ~f:(fun () -> merge_command ()) in
      let statement = Statement.command ~dialect:Dialect.postgresql command in
      Statement.sql_exn ~dialect:Postgresql statement |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" AS (
            DELETE FROM people
          )
        MERGE INTO "raw_rows" AS t0
        USING "raw_rows" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          DELETE
        |}]
    ;;

    let%expect_test "raw RETURNING CTEs compose with a DSL MERGE" =
      let definition =
        Postgresql.Cte.returning
          ~table:Row.table
          ~columns:Row.projection
          (Raw.returning ~output [ Raw.unsafe_sql "DELETE FROM people RETURNING id" ])
      in
      let command = Cte.with_command definition ~f:(fun _ -> merge_command ()) in
      let statement = Statement.command ~dialect:Dialect.postgresql command in
      Statement.sql_exn ~dialect:Postgresql statement |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" (
            "id"
          ) AS (
            DELETE FROM people RETURNING id
          )
        MERGE INTO "raw_rows" AS t0
        USING "raw_rows" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          DELETE
        |}]
    ;;

    let%expect_test "raw CTEs preserve a false predicate in a DSL command" =
      let definition =
        Postgresql.Cte.command (Raw.command [ Raw.unsafe_sql "DELETE FROM people" ])
      in
      let command =
        Cte.with_command definition ~f:(fun () ->
          Update.(
            table Row.table
            |> set Assignment.[ value Row.column 1 ]
            |> where (fun _ -> Condition.false_)
            |> command))
      in
      let statement = Statement.command ~dialect:Dialect.postgresql command in
      Statement.sql_exn ~dialect:Postgresql statement |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" AS (
            DELETE FROM people
          )
        UPDATE "raw_rows"
        SET
          "id" = $1
        WHERE
          FALSE
        |}]
    ;;
  end)
;;

let%test_module "raw multiset text transport" =
  (module struct
    let json_multiset_sql descriptor =
      let nested =
        Raw.select
          ~output:(Raw_sql.Output.field ~name:id (Db_type.option descriptor))
          [ Raw.unsafe_sql "SELECT NULL AS id" ]
      in
      sql Query.(from Row.table |> select (fun _ -> multiset nested))
    ;;

    let%expect_test "raw JSON multiset fields use text transport" =
      json_multiset_sql Db_type.Postgresql.json |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          CAST(
            (
              SELECT
                COALESCE(
                  JSONB_AGG(
                    JSONB_BUILD_ARRAY(
                      CAST(m0."v0" AS TEXT)
                    )
                  ),
                  JSONB_BUILD_ARRAY()
                )
              FROM LATERAL (
                SELECT "__typed_sql_raw"."c0" AS "v0" FROM (
        SELECT NULL AS id
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "raw_rows" AS t0
        |}]
    ;;

    let%expect_test "raw JSONB multiset fields use text transport" =
      json_multiset_sql Db_type.Postgresql.jsonb |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          CAST(
            (
              SELECT
                COALESCE(
                  JSONB_AGG(
                    JSONB_BUILD_ARRAY(
                      CAST(m0."v0" AS TEXT)
                    )
                  ),
                  JSONB_BUILD_ARRAY()
                )
              FROM LATERAL (
                SELECT "__typed_sql_raw"."c0" AS "v0" FROM (
        SELECT NULL AS id
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "raw_rows" AS t0
        |}]
    ;;

    let%expect_test "JSON domain multiset fields preserve the underlying text transport" =
      let descriptor =
        Db_type.Postgresql.named
          ~schema:(Identifier.of_string_exn "public")
          ~name:(Identifier.of_string_exn "document")
          Db_type.Postgresql.jsonb
      in
      json_multiset_sql descriptor |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          CAST(
            (
              SELECT
                COALESCE(
                  JSONB_AGG(
                    JSONB_BUILD_ARRAY(
                      CAST(m0."v0" AS TEXT)
                    )
                  ),
                  JSONB_BUILD_ARRAY()
                )
              FROM LATERAL (
                SELECT "__typed_sql_raw"."c0" AS "v0" FROM (
        SELECT NULL AS id
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "raw_rows" AS t0
        |}]
    ;;
  end)
;;

let%test_module "raw output inspection" =
  (module struct
    let%expect_test "mapped output keeps positional names and database types" =
      let output =
        let%map.Raw_sql.Output id = Raw_sql.Output.field ~name:id Db_type.int
        and name =
          Raw_sql.Output.field ~name:(Identifier.of_string_exn "name") Db_type.text
        in
        object
          method id = id
          method name = name
        end
      in
      let query = Raw.select ~output [ Raw.unsafe_sql "SELECT 1 AS id, 'Ada' AS name" ] in
      let _, inspected =
        Statement.query_many ~dialect:Dialect.postgresql query
        |> Statement.inspect_exn ~dialect:Postgresql
      in
      Statement.sexp_of_output inspected.output
      |> Sexp.to_string_hum
      |> Stdlib.print_endline;
      [%expect
        {|
        (Query_output (cardinality Many)
         (columns
          (((position 1) (name (id)) (db_type int) (dialect_type (integer)))
           ((position 2) (name (name)) (db_type text) (dialect_type (text))))))
        |}]
    ;;

    let%test "output map preserves the decoder's fields" =
      let output = Raw_sql.Output.map output ~f:Int.to_string in
      String.equal (sql (Raw.select ~output [ Raw.unsafe_sql "SELECT 1" ])) "SELECT 1"
    ;;

    let%expect_test "raw statement inspection has a stable structured representation" =
      let statement =
        Statement.query_many
          ~dialect:Dialect.postgresql
          (select [ Raw.unsafe_sql "SELECT 1 AS id" ])
      in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql statement in
      Stdlib.print_endline (Sexp.to_string_hum (Statement.sexp_of_inspection inspection));
      [%expect
        {|
        ((dialect Postgresql) (parameters ())
         (output
          (Query_output (cardinality Many)
           (columns
            (((position 1) (name (id)) (db_type int) (dialect_type (integer)))))))
         (tree (Leaf (kind Query) (mode Static))))
        |}]
    ;;

    let%expect_test "raw codec failures retain the bind position in diagnostics" =
      let db_type =
        Db_type.map
          Db_type.int
          ~encode:(fun _ -> Error "invalid tag")
          ~decode:Result.return
      in
      let query =
        select
          [ Raw.unsafe_sql "SELECT "; Raw.bind Db_type.int (Expr.constant db_type 1) ]
      in
      let statement = Statement.query_many ~dialect:Dialect.postgresql query in
      (match Statement.debug_sql ~dialect:Postgresql ~input:() statement with
       | Ok _ -> failwith "expected codec failure"
       | Error error ->
         Stdlib.print_endline
           (Sexp.to_string_hum (Statement.sexp_of_debug_sql_error error)));
      [%expect
        {|
        (Resolution_failure
         (Codec_error (position 1) (name ()) (message "invalid tag")))
        |}]
    ;;

    let%expect_test "raw and DSL branches retain the inspected statement tree" =
      let raw =
        Statement.query_many
          ~dialect:Dialect.postgresql
          (select [ Raw.unsafe_sql "SELECT 1 AS id" ])
      in
      let dynamic =
        Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
          select [ Raw.unsafe_sql "SELECT 2 AS id" ])
      in
      let postgresql =
        Statement.choose ~when_:(fun () -> true) ~if_true:raw ~if_false:dynamic
      in
      let sqlite =
        Statement.query_many
          ~dialect:Dialect.sqlite
          Query.(from Row.table |> select Row.projection)
      in
      let statement = Statement.choose_dialect ~postgresql ~sqlite in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:() statement in
      Stdlib.print_endline
        (Sexp.to_string_hum (Statement.sexp_of_statement_tree inspection.tree));
      [%expect
        {|
        (Dialect_choice (selected (Postgresql))
         (postgresql
          (Input_choice (selected (true)) (if_true (Leaf (kind Query) (mode Static)))
           (if_false (Leaf (kind Query) (mode Dynamic)))))
         (sqlite (Leaf (kind Query) (mode Static))))
        |}]
    ;;
  end)
;;

let%test_module "raw queries in static statements" =
  (module struct
    module Person = struct
      type t

      let table : t Table.t = Table.v_exn ~schema:"public" "mega_people"
      let id_column = Column.v_exn table "id" Db_type.int64
      let name_column = Column.v_exn table "name" Db_type.text
      let id person = Expr.column person id_column
    end

    let output = Raw_sql.Output.field ~name:(Identifier.of_string_exn "id") Db_type.int64
    let projection person = Projection.expr (Person.id person)

    let raw_select value =
      Raw.select
        ~output
        [ Raw.unsafe_sql "SELECT "
        ; Raw.bind Db_type.int64 value
        ; Raw.unsafe_sql " AS id"
        ]
    ;;

    let%test_unit "one input slot survives UNION, derived relations and CTEs" =
      let statement =
        Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
          let%map.Parameters id = params.expr Db_type.int64 ~get:Fn.id in
          let raw = raw_select id in
          let relation =
            Derived_table.create ~table:Person.table ~columns:projection raw
          in
          let selected =
            Cte.with_result (Cte.select relation) ~f:(fun cte ->
              Query.(from_cte cte |> select projection))
          in
          params.query_many (Query.union_all raw selected))
      in
      let first = Statement.sql_exn ~dialect:Postgresql ~input:1L statement in
      let second = Statement.sql_exn ~dialect:Postgresql ~input:2L statement in
      assert (String.equal first second);
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:2L statement in
      assert (Int.equal (List.length inspection.parameters) 1)
    ;;

    let%test_unit "raw RETURNING exposes its typed relation through a CTE" =
      let returning =
        Raw.returning
          ~output
          [ Raw.unsafe_sql "DELETE FROM public.mega_people WHERE id = "
          ; Raw.bind Db_type.int64 (Expr.constant Db_type.int64 1L)
          ; Raw.unsafe_sql " RETURNING id"
          ]
      in
      let definition =
        Postgresql.Cte.returning ~table:Person.table ~columns:projection returning
      in
      let query =
        Cte.with_result definition ~f:(fun cte ->
          Query.(from_cte cte |> select projection))
      in
      let statement = Statement.query_many ~dialect:Dialect.postgresql query in
      assert (
        String.is_substring
          (Statement.sql_exn ~dialect:Postgresql statement)
          ~substring:"DELETE FROM public.mega_people")
    ;;

    let%test_unit "an effect-only raw CTE preserves the DSL command result" =
      let cleanup =
        Raw.command
          [ Raw.unsafe_sql "DELETE FROM public.mega_people_audit WHERE person_id = "
          ; Raw.bind Db_type.int64 (Expr.constant Db_type.int64 1L)
          ]
      in
      let command =
        Cte.with_command (Postgresql.Cte.command cleanup) ~f:(fun () ->
          Update.(
            table Person.table
            |> set Assignment.[ value Person.name_column "updated" ]
            |> all_rows
            |> command))
      in
      let statement = Statement.command ~dialect:Dialect.postgresql command in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql statement in
      match inspection.output with
      | Statement.Command_output -> ()
      | Statement.Query_output _ -> failwith "expected an affected-row command"
    ;;
  end)
;;
