open! Base
open Typed_sql_pgocaml_ppx
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

let%test_module "extended predicates" =
  (module struct
    let id = I.of_string_exn

    let column ?(native = "int4") name =
      S.column
        ~name:(id name)
        ~db_type:S.Int
        ~nullable:false
        ~postgresql_type:(id "pg_catalog", id native)
        ()
    ;;

    let schema =
      S.v
        [ S.table
            ~schema:(id "public")
            ~name:(id "items")
            ~columns:
              [ column "id"
              ; column ~native:"text" "name"
              ; column ~native:"bool" "active"
              ; column ~native:"numeric" "amount"
              ; column ~native:"json" "document"
              ]
            ()
        ]
    ;;

    let compile source =
      let open Result.Let_syntax in
      let%bind sql = Sql.parse source in
      Statement_plan.create schema sql
    ;;

    let plan source =
      compile source |> Result.map_error ~f:Sql.error_to_string |> Result.ok_or_failwith
    ;;

    let print_error source =
      match compile source with
      | Ok _ -> failwith "expected rejection"
      | Error error -> Stdlib.print_endline (Sql.error_to_string error)
    ;;

    let%test_unit "predicate AST preserves precedence" =
      let query =
        Sql.parse "SELECT id FROM items WHERE NOT active AND id > $id OR name = $name"
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      match query.conditions with
      | Some
          (Sql.Or
             (And (Not (Boolean (Reference _)), Compare (">", _, _)), Compare ("=", _, _)))
        -> ()
      | _ -> failwith "expected NOT, AND, OR precedence"
    ;;

    let%test_unit "BETWEEN consumes its internal AND" =
      let query =
        Sql.parse "SELECT id FROM items WHERE id BETWEEN $low AND $high AND active"
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      match query.conditions with
      | Some (Sql.And (Between _, Boolean _)) -> ()
      | _ -> failwith "expected grouped BETWEEN"
    ;;

    let%expect_test "mixed predicates and pagination infer codecs in source order" =
      let value =
        plan
          "SELECT id FROM items WHERE NOT (active OR id <= $id) AND name NOT ILIKE $?pattern ESCAPE $escape AND id NOT BETWEEN $low AND ${high} AND name IS NOT NULL ORDER BY id OFFSET $offset LIMIT $?limit"
      in
      Stdlib.print_endline value.sql;
      [%expect
        {| SELECT id FROM items WHERE NOT (active OR id <= $1) AND name NOT ILIKE $2 ESCAPE $3 AND id NOT BETWEEN $4 AND $5 AND name IS NOT NULL ORDER BY id OFFSET $6 LIMIT $7 |}];
      assert (
        List.equal
          String.equal
          (List.map value.parameters ~f:(fun value -> Codec.to_string value.codec))
          [ "int32"; "string"; "string"; "int32"; "int32"; "int64"; "int64" ])
    ;;

    let%test_unit "literal bodies never create substitutions" =
      let value =
        plan
          "SELECT id FROM items WHERE name = 'don''t $id $@ids' OR name LIKE 'x\\_%' ESCAPE '\\' AND id = ${id} /* $ignored */"
      in
      assert (Int.equal (List.length value.parameters) 1);
      assert (String.is_substring value.sql ~substring:"'don''t $id $@ids'");
      assert (String.is_substring value.sql ~substring:"id = $1")
    ;;

    let%test "string, signed decimal and exponent literals are accepted" =
      Result.is_ok
        (compile
           "SELECT id FROM items WHERE name = 'Ada' AND amount >= -1.5e+2 AND active = TRUE OR id = NULL")
    ;;

    let%test_unit "a literal supplies a standalone parameter's type" =
      let value =
        plan
          "SELECT id FROM items WHERE $integer = 1 AND $decimal > 1.5 AND $text = 'Ada' AND $boolean = FALSE"
      in
      assert (
        List.equal
          String.equal
          (List.map value.parameters ~f:(fun value -> Codec.to_string value.codec))
          [ "int32"; "string"; "string"; "bool" ])
    ;;

    let%test "comparisons can place a parameter before a column" =
      Result.is_ok (compile "SELECT id FROM items WHERE $id < id")
    ;;

    let%test "mixed numeric columns have comparisons" =
      Result.is_ok (compile "SELECT id FROM items WHERE id <= amount")
    ;;

    let%test "IN accepts columns, parameters and literals" =
      Result.is_ok (compile "SELECT id FROM items WHERE id IN (1, $id, id)")
    ;;

    let%test "boolean NULL keeps SQL three-valued semantics" =
      Result.is_ok (compile "SELECT id FROM items WHERE NOT NULL OR active")
    ;;

    let%test "JSON permits IS NULL without an equality codec" =
      Result.is_ok (compile "SELECT id FROM items WHERE document IS NULL")
    ;;

    let%test "LIKE rejects numeric operands" =
      Result.is_error (compile "SELECT id FROM items WHERE id LIKE $pattern")
    ;;

    let%test "boolean predicates reject numeric operands" =
      Result.is_error (compile "SELECT id FROM items WHERE id")
    ;;

    let%test "incompatible column types are rejected" =
      Result.is_error (compile "SELECT id FROM items WHERE id = name")
    ;;

    let%test "unknown predicate columns are rejected" =
      Result.is_error (compile "SELECT id FROM items WHERE missing IS NULL")
    ;;

    let%test "JSON has no ordering operator" =
      Result.is_error (compile "SELECT id FROM items WHERE document > $value")
    ;;

    let%test "ordinary IS NULL cannot infer an isolated parameter" =
      Result.is_error (compile "SELECT id FROM items WHERE $unknown IS NULL")
    ;;

    let%test "two untyped parameters cannot infer each other" =
      Result.is_error (compile "SELECT id FROM items WHERE $left = $right")
    ;;

    let%test "LIMIT ALL and independent OFFSET are accepted" =
      Result.is_ok (compile "SELECT id FROM items OFFSET 2 LIMIT ALL")
    ;;

    let%test "optional pagination parameters use int64" =
      Result.is_ok (compile "SELECT id FROM items LIMIT $?limit OFFSET ${offset}")
    ;;

    let%test "negative pagination remains a server check" =
      Result.is_ok (compile "SELECT id FROM items LIMIT -1")
    ;;

    let%test "fractional pagination is rejected" =
      Result.is_error (compile "SELECT id FROM items LIMIT 1.5")
    ;;

    let%test "pagination does not refer to rows" =
      Result.is_error (compile "SELECT id FROM items OFFSET id")
    ;;

    let%test "repeated pagination is rejected" =
      Result.is_error (compile "SELECT id FROM items LIMIT 1 LIMIT 2")
    ;;

    let%test "UPDATE cannot acquire LIMIT" =
      Result.is_error (compile "UPDATE items SET id = $id LIMIT 1")
    ;;

    let%test "E-strings stay unsupported" =
      Result.is_error (compile "SELECT id FROM items WHERE name = E'escape'")
    ;;

    let%test "dollar quoting stays unsupported" =
      Result.is_error (compile "SELECT id FROM items WHERE name = $$text$$")
    ;;

    let%test "invalid exponents produce a diagnostic" =
      Result.is_error (compile "SELECT id FROM items WHERE id = 1e+")
    ;;

    let%test "unterminated literals produce a diagnostic" =
      Result.is_error (compile "SELECT id FROM items WHERE name = 'unfinished")
    ;;

    let%test "list substitutions outside IN are rejected" =
      Result.is_error (compile "SELECT id FROM items WHERE id = $@ids")
    ;;

    let%test "a native array is required for ANY" =
      Result.is_error (compile "SELECT id FROM items WHERE id = ANY(id)")
    ;;

    let%test_unit "fixed IN uses a common PostgreSQL numeric type" =
      let value = plan "SELECT id FROM items WHERE $value IN (id, 1.5)" in
      assert (
        List.equal
          String.equal
          (List.map value.parameters ~f:(fun parameter -> Codec.to_string parameter.codec))
          [ "string" ])
    ;;

    let%test "signed fractional literals can omit the integer part" =
      Result.is_ok (compile "SELECT id FROM items WHERE amount >= -.5 AND amount < +.5")
    ;;

    let%expect_test "duplicate pagination diagnostic" =
      print_error "SELECT id FROM items LIMIT 1 OFFSET 0 LIMIT 2";
      [%expect {| SQL byte 38: duplicate pagination clause |}]
    ;;
  end)
;;
