open! Base
open Typed_sql
module Q = Cached_queries.Queries
module K = Typed_sql_ppx_cache.Query_kind

let%test_module "cached quotation SQL" =
  (module struct
    let%expect_test "object results and Expr input compile offline" =
      Statement.sql_exn ~dialect:Postgresql ~input:2 Q.find |> Stdlib.print_endline;
      [%expect {| SELECT id, name FROM typed_sql_query_items WHERE id = $1 |}]
    ;;

    let%expect_test "INSERT RETURNING compiles offline" =
      Statement.sql_exn ~dialect:Postgresql ~input:(2, "Ada") Q.insert
      |> Stdlib.print_endline;
      [%expect
        {| INSERT INTO typed_sql_query_items (id, name) VALUES ($1, $2) RETURNING id, name |}]
    ;;

    let%expect_test "UPDATE parameters follow SQL occurrence order" =
      Statement.sql_exn ~dialect:Postgresql ~input:(2, "Ada") Q.update
      |> Stdlib.print_endline;
      [%expect {| UPDATE typed_sql_query_items SET name = $1 WHERE id = $2 |}]
    ;;

    let%expect_test "DELETE compiles offline" =
      Statement.sql_exn ~dialect:Postgresql ~input:2 Q.delete |> Stdlib.print_endline;
      [%expect {| DELETE FROM typed_sql_query_items WHERE id = $1 |}]
    ;;

    let%expect_test "optional input retains a trailing comment without a semicolon" =
      Statement.sql_exn ~dialect:Postgresql ~input:None Q.nullable |> Stdlib.print_endline;
      [%expect {| SELECT $1::text AS name -- trailing comment |}]
    ;;

    let%expect_test "raw and DSL UNION ALL compile offline" =
      Statement.sql_exn ~dialect:Postgresql Q.union |> Stdlib.print_endline;
      [%expect
        {|
        SELECT *
        FROM (
          SELECT 1::int4 AS id
        ) AS s0
        UNION ALL
        SELECT *
        FROM (
          SELECT
            t0."id"
          FROM "typed_sql_query_items" AS t0
        ) AS s0
        |}]
    ;;

    let%expect_test "raw output fields can become a derived relation" =
      Statement.sql_exn ~dialect:Postgresql Q.derived |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          t0."id"
        FROM (
          SELECT "__typed_sql_raw"."c0" AS "id" FROM (
        SELECT 1::int4 AS id
        ) AS "__typed_sql_raw" ("c0")
        ) AS t0
        |}]
    ;;

    let%expect_test "raw output fields can become a CTE" =
      Statement.sql_exn ~dialect:Postgresql Q.cte |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" (
            "id"
          ) AS (
            SELECT 1::int4 AS id
          )
        SELECT
          t0."id"
        FROM "c0" AS t0
        |}]
    ;;

    let%expect_test "raw rows compose with a DSL multiset" =
      Statement.sql_exn ~dialect:Postgresql Q.nested |> Stdlib.print_endline;
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
        SELECT 1::int4 AS id
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "typed_sql_query_items" AS t0
        |}]
    ;;

    let%expect_test "raw JSONB rows use text transport inside a multiset" =
      Statement.sql_exn ~dialect:Postgresql Q.nested_json |> Stdlib.print_endline;
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
        SELECT value FROM typed_sql_query_json ORDER BY id
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "typed_sql_query_items" AS t0
        |}]
    ;;

    let%expect_test "raw JSON rows use text transport inside a multiset" =
      Statement.sql_exn ~dialect:Postgresql Q.nested_json_text |> Stdlib.print_endline;
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
        SELECT value::json AS value FROM typed_sql_query_json ORDER BY id
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "typed_sql_query_items" AS t0
        |}]
    ;;

    let%expect_test "a data modifying raw CTE remains a top level statement" =
      Statement.sql_exn ~dialect:Postgresql Q.modifying_cte |> Stdlib.print_endline;
      [%expect
        {|
        WITH inserted AS (INSERT INTO typed_sql_query_items VALUES (7, 'CTE') RETURNING id) SELECT id FROM inserted
        |}]
    ;;

    let%expect_test "a nested row lock composes with a multiset" =
      Statement.sql_exn ~dialect:Postgresql Q.nested_locked |> Stdlib.print_endline;
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
        SELECT id FROM typed_sql_query_items WHERE EXISTS (SELECT 1 FROM typed_sql_query_items FOR UPDATE)
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "typed_sql_query_items" AS t0
        |}]
    ;;

    let%expect_test "a CTE containing a row lock composes with a multiset" =
      Statement.sql_exn ~dialect:Postgresql Q.nested_locked_cte |> Stdlib.print_endline;
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
        WITH locked AS (SELECT id FROM typed_sql_query_items FOR UPDATE) SELECT id FROM locked
        ) AS "__typed_sql_raw" ("c0")
              ) AS m0
            )
            AS TEXT
          )
        FROM "typed_sql_query_items" AS t0
        |}]
    ;;
  end)
;;

let%test_module "statement kind classifier" =
  (module struct
    let select sql =
      match (K.analyze sql).operation with
      | K.Select -> true
      | _ -> false
    ;;

    let%test "CTE bodies and literal keywords are not the outside command" =
      select "WITH x AS (SELECT 'DELETE') SELECT * FROM x"
    ;;

    let%test "data modifying CTE requires top level" =
      (K.analyze "WITH x AS (DELETE FROM t RETURNING id) SELECT * FROM x").top_level_only
    ;;

    let%test "locking SELECT requires top level" =
      (K.analyze "SELECT * FROM t FOR UPDATE").top_level_only
    ;;

    let%test "quoted keywords do not restrict SELECT" =
      not (K.analyze "SELECT $$for update$$, 'for share' /* for update */").top_level_only
    ;;

    let%test "CTE outside command can be DML" =
      match
        (K.analyze "WITH x AS MATERIALIZED (SELECT 1) UPDATE t SET id=1").operation
      with
      | K.Update -> true
      | _ -> false
    ;;

    let%test "unknown WITH syntax is rejected" =
      match
        (K.analyze
           "WITH x AS (SELECT 1) SEARCH DEPTH FIRST BY id SET pos SELECT * FROM x")
          .operation
      with
      | K.Unsupported -> true
      | _ -> false
    ;;
  end)
;;

let%test "E-string continuation preserves escape mode during classification" =
  not
    (K.analyze
       {sql|SELECT E'first'
'it\'s FOR UPDATE'|sql})
      .top_level_only
;;

let%test_module "logical query cache" =
  (module struct
    module C = Typed_sql_ppx_cache.Query_cache
    module S = Typed_sql_schema.Schema_ir
    module I = Typed_sql_schema.Identifier

    let int4 =
      { S.schema = I.of_string_exn "pg_catalog"
      ; name = I.of_string_exn "int4"
      ; kind = S.Native_scalar
      }
    ;;

    let entry =
      { C.sql = "SELECT $1::int4 AS id"
      ; kind = C.Select
      ; top_level_only = false
      ; parameters = [ int4 ]
      ; result = Some [ { C.name = "id"; typ = int4; nullable = true } ]
      }
    ;;

    let make entries = C.create ~role:"fixture" ~search_path:"public" entries

    let%test "logical cache has no driver codecs" =
      match make [ entry ] with
      | Error _ -> false
      | Ok cache -> not (String.is_substring (C.to_string cache) ~substring:"codec")
    ;;

    let%test "v2 roundtrip is deterministic" =
      match make [ entry ] with
      | Error _ -> false
      | Ok cache ->
        let json = C.to_string cache in
        (match C.of_string json with
         | Error _ -> false
         | Ok cache -> String.equal (C.to_string cache) json)
    ;;

    let%test "unexpected cache format versions are rejected" =
      let cache = make [ entry ] |> Result.ok_or_failwith in
      let source = C.to_string cache in
      List.for_all [ 1; 3 ] ~f:(fun version ->
        C.of_string
          (String.substr_replace_first
             source
             ~pattern:"\"version\": 2"
             ~with_:("\"version\": " ^ Int.to_string version))
        |> Result.is_error)
    ;;

    let%test "cache cannot relabel DML as a nestable SELECT" =
      Result.is_error (make [ { entry with sql = "DELETE FROM t RETURNING id" } ])
    ;;

    let%test "cache cannot remove placement restrictions" =
      Result.is_error (make [ { entry with sql = "SELECT id FROM t FOR UPDATE" } ])
    ;;

    let%test "cache cannot relabel row results as commands" =
      Result.is_error
        (make
           [ { entry with
               sql = "DELETE FROM t RETURNING id"
             ; kind = C.Command
             ; top_level_only = true
             }
           ])
    ;;
  end)
;;

let%test "DML cache entries cannot contain several statements" =
  match (K.analyze "DELETE FROM t; SELECT 1").operation with
  | K.Unsupported -> true
  | _ -> false
;;

let%test_module "direct statement SQL" =
  (module struct
    let%expect_test "direct object statement accepts runtime input" =
      Statement.sql_exn ~dialect:Postgresql ~input:42 Q.find_direct
      |> Stdlib.print_endline;
      [%expect {| SELECT id, name FROM typed_sql_query_items WHERE id = $1 |}]
    ;;

    let%expect_test "direct record statement binds input fields" =
      Statement.sql_exn
        ~dialect:Postgresql
        ~input:{ Q.id = 42; name = "Ada" }
        Q.insert_direct
      |> Stdlib.print_endline;
      [%expect
        {| INSERT INTO typed_sql_query_items (id, name) VALUES ($1, $2) RETURNING id, name |}]
    ;;

    let%expect_test "direct tuple statement binds input fields" =
      Statement.sql_exn ~dialect:Postgresql ~input:(42, "Ada") Q.tuple_direct
      |> Stdlib.print_endline;
      [%expect
        {| INSERT INTO typed_sql_query_items (id, name) VALUES ($1, $2) RETURNING id, name |}]
    ;;

    let%expect_test "direct optional statement preserves the trailing comment" =
      Statement.sql_exn ~dialect:Postgresql ~input:None Q.nullable_direct
      |> Stdlib.print_endline;
      [%expect {| SELECT $1::text AS name -- trailing comment |}]
    ;;

    let%expect_test "parameterless direct statement has unit input" =
      Statement.sql_exn ~dialect:Postgresql ~input:() Q.constant_statement
      |> Stdlib.print_endline;
      [%expect {| SELECT 1::int4 AS id |}]
    ;;

    let%expect_test "direct command binds runtime input" =
      Statement.sql_exn ~dialect:Postgresql ~input:42 Q.delete_direct
      |> Stdlib.print_endline;
      [%expect {| DELETE FROM typed_sql_query_items WHERE id = $1 |}]
    ;;

    let%expect_test "direct record expression uses the input field" =
      Statement.sql_exn
        ~dialect:Postgresql
        ~input:{ Q.id = 42; name = "Ada" }
        Q.record_expression_direct
      |> Stdlib.print_endline;
      [%expect {| SELECT id, name FROM typed_sql_query_items WHERE id = $1 |}]
    ;;
  end)
;;

let%test "input getters are deferred until binding and read each new input" =
  let calls = ref 0 in
  let next_id () =
    Int.incr calls;
    !calls
  in
  let _ = Statement.sql_exn ~dialect:Postgresql Q.expression_direct in
  assert (Int.equal !calls 0);
  let _, first =
    Statement.inspect_exn ~dialect:Postgresql ~input:next_id Q.expression_direct
  in
  let _, second =
    Statement.inspect_exn ~dialect:Postgresql ~input:next_id Q.expression_direct
  in
  Int.equal !calls 2
  && List.for_all2_exn [ first; second ] [ "1"; "2" ] ~f:(fun inspection expected ->
    match inspection.parameters with
    | [ { value = Some (Encoded value); _ } ] -> String.equal value expected
    | _ -> false)
;;

let%test "one top level statement binds different values without changing SQL" =
  let inspect id = Statement.inspect_exn ~dialect:Postgresql ~input:id Q.find_direct in
  let first_sql, first = inspect 1 in
  let second_sql, second = inspect 2 in
  String.equal first_sql second_sql
  && List.for_all2_exn [ first; second ] [ "1"; "2" ] ~f:(fun inspection expected ->
    match inspection.parameters with
    | [ { value = Some (Encoded value); _ } ] -> String.equal value expected
    | _ -> false)
;;

let%test "record and tuple input declare the same typed SQL parameters" =
  String.equal
    (Statement.sql_exn
       ~dialect:Postgresql
       ~input:{ Q.id = 42; name = "Ada" }
       Q.insert_direct)
    (Statement.sql_exn ~dialect:Postgresql ~input:(42, "Ada") Q.tuple_direct)
;;

let%test "collector finds both direct statement forms" =
  let source =
    {ocaml|let q = [%pgsql.statement fun id -> "SELECT $id"]
let o = [%pgsql.statement.object fun id -> "nullable-results" "SELECT $id AS id"]|ocaml}
  in
  match
    Typed_sql_ppx_cache.Query_source.collect_exn
      (Ppxlib.Parse.implementation (Stdlib.Lexing.from_string source))
  with
  | [ first; second ] ->
    String.equal first.query.sql "SELECT $1"
    && String.equal second.query.sql "SELECT $1 AS id"
  | _ -> false
;;

let%test "record input expressions use the annotated runtime input" =
  let _, inspection =
    Statement.inspect_exn
      ~dialect:Postgresql
      ~input:{ Q.id = 42; name = "Ada" }
      Q.record_expression_direct
  in
  match inspection.parameters with
  | [ { value = Some (Encoded value); _ } ] -> String.equal value "42"
  | _ -> false
;;

let%test "a row lock inside a subquery does not restrict the enclosing SELECT" =
  not
    (K.analyze "SELECT id FROM people WHERE EXISTS (SELECT 1 FROM jobs FOR UPDATE)")
      .top_level_only
;;

let%test "a locking SELECT CTE can be nested with its enclosing SELECT" =
  not
    (K.analyze "WITH jobs AS (SELECT id FROM people FOR UPDATE) SELECT id FROM jobs")
      .top_level_only
;;

let%test "data modifying CTE restrictions survive nested WITH clauses" =
  (K.analyze
     "WITH jobs AS (WITH deleted AS (DELETE FROM people RETURNING id) SELECT id FROM deleted) SELECT id FROM jobs")
    .top_level_only
;;

let%test_module "cached statement inspection" =
  (module struct
    let%expect_test "object output preserves cached column names and types" =
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:2 Q.find in
      Statement.sexp_of_output inspection.output
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

    let%expect_test "nullable-results makes all object fields nullable" =
      let _, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:2 Q.nullable_people_direct
      in
      Statement.sexp_of_output inspection.output
      |> Sexp.to_string_hum
      |> Stdlib.print_endline;
      [%expect
        {|
        (Query_output (cardinality Many)
         (columns
          (((position 1) (name (id)) (db_type "option(int)")
            (dialect_type (integer)))
           ((position 2) (name (name)) (db_type "option(text)")
            (dialect_type (text))))))
        |}]
    ;;

    let%expect_test "direct statement optional binds preserve NULL" =
      let _, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:None Q.nullable_direct
      in
      Statement.sexp_of_inspection inspection
      |> Sexp.to_string_hum
      |> Stdlib.print_endline;
      [%expect
        {|
        ((dialect Postgresql)
         (parameters
          (((position 1) (placeholder $1) (name ()) (db_type "option(text)")
            (dialect_type (text)) (value (Null)))))
         (output
          (Query_output (cardinality Many)
           (columns
            (((position 1) (name (name)) (db_type "option(text)")
              (dialect_type (text)))))))
         (tree (Leaf (kind Query) (mode Static))))
        |}]
    ;;

    let%expect_test "direct DML without RETURNING produces command output" =
      let _, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:42 Q.delete_direct
      in
      Statement.sexp_of_inspection inspection
      |> Sexp.to_string_hum
      |> Stdlib.print_endline;
      [%expect
        {|
        ((dialect Postgresql)
         (parameters
          (((position 1) (placeholder $1) (name ()) (db_type int)
            (dialect_type (integer)) (value ((Encoded 42))))))
         (output Command_output) (tree (Leaf (kind Command) (mode Static))))
        |}]
    ;;

    let%expect_test "UPDATE binding follows the rendered parameter order" =
      let _, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:(2, "Ada") Q.update
      in
      List.iter inspection.parameters ~f:(fun parameter ->
        Statement.sexp_of_parameter parameter
        |> Sexp.to_string_hum
        |> Stdlib.print_endline);
      [%expect
        {|
        ((position 1) (placeholder $1) (name ()) (db_type text) (dialect_type (text))
         (value ((Encoded Ada))))
        ((position 2) (placeholder $2) (name ()) (db_type int)
         (dialect_type (integer)) (value ((Encoded 2))))
        |}]
    ;;
  end)
;;
