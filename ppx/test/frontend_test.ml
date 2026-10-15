open! Base
open Typed_sql_pgocaml_ppx
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

let%test_module "single-table SELECT frontend" =
  (module struct
    let id = I.of_string_exn

    let column ?(nullable = false) ?(native = Some "int4") name =
      S.column
        ~name:(id name)
        ~db_type:S.Int
        ~nullable
        ?postgresql_type:(Option.map native ~f:(fun name -> id "pg_catalog", id name))
        ()
    ;;

    let schema =
      S.v
        [ S.table
            ~schema:(id "public")
            ~name:(id "people")
            ~columns:
              [ column "id"
              ; column ~nullable:true "note"
              ; column ~native:(Some "_int4") "numbers"
              ]
            ()
        ]
    ;;

    let compile source =
      let open Result.Let_syntax in
      let%bind query = Sql.parse source in
      Statement_plan.create schema query
    ;;

    let print_error source =
      match compile source with
      | Ok _ -> failwith "expected rejection"
      | Error error -> Stdlib.print_endline (Sql.error_to_string error)
    ;;

    let%test_unit "comments and grouped conjunctions are fully consumed" =
      let plan =
        compile
          "/* outer /* inner */ end */ SeLeCt p.id FROM public.people p -- comment\nWHERE (p.id = $id AND (p.note = $?note)) ORDER BY p.id ASC;"
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      assert (Int.equal (List.length plan.parameters) 2);
      assert (String.is_substring plan.sql ~substring:"p.id = $1 AND (p.note = $2)")
    ;;

    let%test_unit "wildcards preserve snapshot order" =
      let schema =
        S.v
          [ S.table
              ~schema:(id "public")
              ~name:(id "people")
              ~columns:[ column "second"; column "first" ]
              ()
          ]
      in
      let query =
        Sql.parse "SELECT p.* FROM people AS p"
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      let plan =
        Statement_plan.create schema query
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      assert (
        List.equal
          String.equal
          (List.map (Statement_plan.fields plan) ~f:(fun field -> field.name))
          [ "second"; "first" ])
    ;;

    let%test "unused unsupported columns do not block a supported projection" =
      Result.is_ok (compile "SELECT id FROM people")
    ;;

    let%expect_test "bind placeholders preserve SQL without parameter values" =
      let plan =
        compile
          "SELECT id FROM people WHERE (id = $id AND note = $?note) ORDER BY id DESC"
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      Stdlib.print_endline plan.sql;
      [%expect {| SELECT id FROM people WHERE (id = $1 AND note = $2) ORDER BY id DESC |}]
    ;;

    let%expect_test "unknown column diagnostic" =
      print_error "SELECT missing FROM people";
      [%expect {| SQL byte 7: unknown column: missing |}]
    ;;

    let%expect_test "unsupported trailing grammar diagnostic" =
      print_error "SELECT id FROM people LIMIT id";
      [%expect {| SQL byte 28: pagination cannot refer to a column |}]
    ;;

    let%expect_test "source alias diagnostic" =
      print_error "SELECT people.id FROM people AS p";
      [%expect {| SQL byte 7: column qualifier does not name the statement source |}]
    ;;

    let%expect_test "unsupported array diagnostic" =
      print_error "SELECT numbers FROM people";
      [%expect
        {| SQL byte 7: unsupported PostgreSQL type: pg_catalog._int4; refresh snapshot with nested native metadata |}]
    ;;

    let%test "rejects multiple statements" =
      Result.is_error (compile "SELECT id FROM people; SELECT id FROM people")
    ;;

    let%test "rejects ambiguous joined columns" =
      Result.is_error (compile "SELECT id FROM people JOIN people p ON true")
    ;;

    let%test "accepts SQL literal equality" =
      Result.is_ok (compile "SELECT id FROM people WHERE id = 1")
    ;;

    let%test "accepts OR conditions" =
      Result.is_ok (compile "SELECT id FROM people WHERE id = $id OR id = $id")
    ;;

    let%test "accepts aggregates" = Result.is_ok (compile "SELECT count(*) FROM people")
    let%test "accepts DISTINCT" = Result.is_ok (compile "SELECT DISTINCT id FROM people")

    let%test "accepts projection arithmetic" =
      Result.is_ok (compile "SELECT id + id FROM people")
    ;;

    let%test "rejects unknown sort columns" =
      Result.is_error (compile "SELECT id FROM people ORDER BY missing")
    ;;

    let%test "rejects unterminated comments" =
      Result.is_error (compile "SELECT id FROM people /* unterminated")
    ;;

    let%test "rejects list parameters" =
      Result.is_error (compile "SELECT id FROM people WHERE id = $@ids")
    ;;

    let%test "rejects positional SQL parameters" =
      Result.is_error (compile "SELECT id FROM people WHERE id = $1")
    ;;

    let%test "rejects unterminated OCaml expressions" =
      Result.is_error (compile "SELECT id FROM people WHERE id = ${invalid")
    ;;

    let%test "rejects empty OCaml expressions" =
      Result.is_error (compile "SELECT id FROM people WHERE id = ${}")
    ;;

    let%test "rejects empty quoted identifiers" =
      Result.is_error (compile "SELECT \"\" FROM people")
    ;;

    let%test "rejects trailing DDL" =
      Result.is_error (compile "SELECT id FROM people WHERE id = ${1}; DROP TABLE people")
    ;;

    let%test_unit "missing exact metadata is rejected" =
      let schema =
        S.v
          [ S.table
              ~schema:(id "public")
              ~name:(id "people")
              ~columns:[ column ~native:None "id" ]
              ()
          ]
      in
      let query =
        Sql.parse "SELECT id FROM people"
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      assert (Result.is_error (Statement_plan.create schema query))
    ;;
  end)
;;
