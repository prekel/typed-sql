open! Base
open Typed_sql_pgocaml_ppx
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

let%test_module "INNER JOIN resolution" =
  (module struct
    let column ?(nullable = false) name db_type native =
      S.column
        ~name:(I.of_string_exn name)
        ~db_type
        ~nullable
        ~postgresql_type:(I.of_string_exn "pg_catalog", I.of_string_exn native)
        ()
    ;;

    let people schema =
      S.table
        ~schema:(I.of_string_exn schema)
        ~name:(I.of_string_exn "join_people")
        ~columns:
          [ column "id" S.Int "int4"
          ; column "name" S.Text "text"
          ; column ~nullable:true "note" S.Text "text"
          ]
        ()
    ;;

    let schema =
      S.v
        [ people "public"
        ; people "archive"
        ; S.table
            ~schema:(I.of_string_exn "public")
            ~name:(I.of_string_exn "join_links")
            ~columns:
              [ column "id" S.Int "int4"
              ; column "person_id" S.Int "int4"
              ; column ~nullable:true "label" S.Text "text"
              ; column "active" S.Bool "bool"
              ]
            ()
        ]
    ;;

    let compile source =
      let open Result.Let_syntax in
      let%bind query = Sql.parse source in
      Statement_plan.create schema query
    ;;

    let plan source =
      compile source |> Result.map_error ~f:Sql.error_to_string |> Result.ok_or_failwith
    ;;

    let print_error source =
      match compile source with
      | Error error -> Stdlib.print_endline (Sql.error_to_string error)
      | Ok _ -> failwith "expected rejection"
    ;;

    let%test "chained inner joins see preceding sources" =
      Result.is_ok
        (compile
           "SELECT p.name, l.label, other.name FROM join_people p INNER JOIN join_links AS l ON p.id = l.person_id JOIN join_people other ON other.id = p.id WHERE l.active ORDER BY other.id")
    ;;

    let%test "ON predicates use the existing boolean grammar" =
      Result.is_ok
        (compile
           "SELECT p.name FROM join_people p JOIN join_links l ON NOT (p.id <> l.person_id) AND (l.label IS NULL OR l.label ILIKE $pattern) AND l.id BETWEEN 1 AND 10 AND p.id IN (1, 2)")
    ;;

    let%test "unqualified ON columns must resolve uniquely" =
      Result.is_error
        (compile "SELECT name, label FROM join_people JOIN join_links ON id = person_id")
    ;;

    let%test "unique unqualified projection resolves" =
      Result.is_ok
        (compile
           "SELECT name, label FROM join_people p JOIN join_links l ON p.id = l.person_id")
    ;;

    let%expect_test "ambiguous unqualified projection" =
      print_error "SELECT id FROM join_people p JOIN join_links l ON p.id = l.person_id";
      [%expect {| SQL byte 7: ambiguous column: id |}]
    ;;

    let%test "ambiguous ON reference is rejected" =
      Result.is_error
        (compile "SELECT p.id FROM join_people p JOIN join_links l ON id = person_id")
    ;;

    let%test "ON cannot see subsequent sources" =
      Result.is_error
        (compile
           "SELECT p.id FROM join_people p JOIN join_links l ON other.id = l.person_id JOIN join_people other ON other.id = p.id")
    ;;

    let%test "ON can refer to its own source" =
      Result.is_ok
        (compile "SELECT p.id FROM join_people p JOIN join_links l ON l.active")
    ;;

    let%test "aliases hide original qualified names" =
      Result.is_error
        (compile
           "SELECT public.join_people.id FROM public.join_people p JOIN join_links l ON p.id = l.person_id")
    ;;

    let%test "schema-qualified sources without aliases" =
      Result.is_ok
        (compile
           "SELECT public.join_people.id, archive.join_people.name FROM public.join_people JOIN archive.join_people ON public.join_people.id = archive.join_people.id")
    ;;

    let%test "same exposed name in different schemas is ambiguous without schema" =
      Result.is_error
        (compile
           "SELECT join_people.id FROM public.join_people JOIN archive.join_people ON true")
    ;;

    let%test "duplicate aliases are rejected" =
      Result.is_error (compile "SELECT p.id FROM join_people p JOIN join_links p ON true")
    ;;

    let%test "unaliased self join is rejected" =
      Result.is_error (compile "SELECT name FROM join_people JOIN join_people ON true")
    ;;

    let%test "unknown joined table is rejected" =
      Result.is_error (compile "SELECT p.id FROM join_people p JOIN missing m ON true")
    ;;

    let%test "unknown joined column is rejected" =
      Result.is_error
        (compile "SELECT l.missing FROM join_people p JOIN join_links l ON true")
    ;;

    let%test "incompatible ON operand types are rejected" =
      Result.is_error
        (compile
           "SELECT p.id FROM join_people p JOIN join_links l ON p.name = l.person_id")
    ;;

    let%test "wildcards preserve source and column order" =
      let fields =
        Statement_plan.fields
          (plan "SELECT * FROM join_people p JOIN join_links l ON true")
      in
      List.equal
        String.equal
        (List.map fields ~f:(fun field -> field.Statement_plan.name))
        [ "id"; "name"; "note"; "id"; "person_id"; "label"; "active" ]
    ;;

    let%test "qualified wildcards preserve projection order" =
      let fields =
        Statement_plan.fields
          (plan
             "SELECT l.*, p.name AS person FROM join_people p JOIN join_links l ON true")
      in
      List.equal
        String.equal
        (List.map fields ~f:(fun field -> field.Statement_plan.name))
        [ "id"; "person_id"; "label"; "active"; "person" ]
    ;;

    let%test "inner join retains attribute nullability" =
      let fields =
        Statement_plan.fields
          (plan
             "SELECT p.name, l.label FROM join_people p JOIN join_links l ON p.id = l.person_id WHERE l.label IS NOT NULL")
      in
      List.equal
        Bool.equal
        (List.map fields ~f:(fun field -> field.Statement_plan.nullable))
        [ false; true ]
    ;;

    let%expect_test "parameters retain lexical SQL order across joins and WHERE" =
      let result =
        plan
          "SELECT p.id FROM join_people p JOIN join_links l ON p.id = l.person_id AND l.label = $?label JOIN join_people other ON other.id = $id WHERE p.name = $name ORDER BY l.id LIMIT $limit OFFSET $offset"
      in
      Stdlib.print_endline result.sql;
      [%expect
        {| SELECT p.id FROM join_people p JOIN join_links l ON p.id = l.person_id AND l.label = $1 JOIN join_people other ON other.id = $2 WHERE p.name = $3 ORDER BY l.id LIMIT $4 OFFSET $5 |}];
      assert (
        List.equal
          String.equal
          (List.map result.parameters ~f:(fun parameter ->
             Codec.to_string parameter.codec))
          [ "string"; "int32"; "string"; "int64"; "int64" ])
    ;;

    let%test "JOIN requires ON" =
      Result.is_error
        (compile "SELECT p.id FROM join_people p JOIN join_links l WHERE true")
    ;;

    let%test "outer joins are supported" =
      Result.is_ok
        (compile "SELECT p.id FROM join_people p LEFT JOIN join_links l ON true")
    ;;

    let%test "right joins are supported" =
      Result.is_ok
        (compile "SELECT p.id FROM join_people p RIGHT JOIN join_links l ON true")
    ;;

    let%test "full joins are supported" =
      Result.is_ok
        (compile "SELECT p.id FROM join_people p FULL JOIN join_links l ON true")
    ;;

    let%test "cross joins are supported" =
      Result.is_ok (compile "SELECT p.id FROM join_people p CROSS JOIN join_links l")
    ;;

    let%test "natural joins are supported" =
      Result.is_ok (compile "SELECT p.id FROM join_people p NATURAL JOIN join_links l")
    ;;

    let%test "USING is supported" =
      Result.is_ok (compile "SELECT p.id FROM join_people p JOIN join_links l USING (id)")
    ;;

    let%test "comma sources are supported" =
      Result.is_ok (compile "SELECT p.id FROM join_people p, join_links l")
    ;;

    let%test "parenthesized joined sources are supported" =
      Result.is_ok (compile "SELECT p.id FROM (join_people p JOIN join_links l ON true)")
    ;;

    let%test "JOIN is unavailable in UPDATE" =
      Result.is_error
        (compile
           "UPDATE join_people p JOIN join_links l ON p.id = l.person_id SET name = $name")
    ;;
  end)
;;
