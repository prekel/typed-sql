open! Base
open Typed_sql_pgocaml_ppx
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

let%test_module "single-table DML frontend" =
  (module struct
    let id = I.of_string_exn

    let column ?primary_key_position ?(native = "int4") name =
      S.column
        ~name:(id name)
        ~db_type:S.Int
        ~nullable:false
        ?primary_key_position
        ~postgresql_type:(id "pg_catalog", id native)
        ()
    ;;

    let schema =
      S.v
        [ S.table
            ~schema:(id "public")
            ~name:(id "items")
            ~columns:
              [ column ~primary_key_position:1 "tenant"
              ; column ~primary_key_position:2 "id"
              ; column ~native:"text" "name"
              ; column ~native:"varchar" "short_name"
              ; column ~native:"json" "document"
              ; column ~native:"_int4" "numbers"
              ]
            ~unique_constraints:[ S.unique_constraint [ id "name" ] ]
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
      | Ok _ -> failwith "expected rejection"
      | Error error -> Stdlib.print_endline (Sql.error_to_string error)
    ;;

    let%expect_test "parameters span VALUES, SET and conflict WHERE in source order" =
      let value =
        plan
          "INSERT INTO items AS i (tenant, id, name) VALUES ($tenant, $id, $name), (${tenant}, ${id}, DEFAULT) ON CONFLICT (id, tenant) DO UPDATE SET name = $?replacement WHERE (i.id = $filter AND EXCLUDED.tenant = $tenant) RETURNING i.id"
      in
      Stdlib.print_endline value.sql;
      [%expect
        {| INSERT INTO items AS i (tenant, id, name) VALUES ($1, $2, $3), ($4, $5, DEFAULT) ON CONFLICT (id, tenant) DO UPDATE SET name = $6 WHERE (i.id = $7 AND EXCLUDED.tenant = $8) RETURNING i.id |}];
      assert (
        List.equal
          String.equal
          (List.map value.parameters ~f:(fun parameter -> Codec.to_string parameter.codec))
          [ "int32"; "int32"; "string"; "int32"; "int32"; "string"; "int32"; "int32" ])
    ;;

    let%test "DEFAULT VALUES is a command without typechecking unused columns" =
      match (plan "INSERT INTO items DEFAULT VALUES").result with
      | Command -> true
      | Rows _ -> false
    ;;

    let%test_unit "wildcard RETURNING preserves snapshot column order" =
      let schema =
        S.v
          [ S.table
              ~schema:(id "public")
              ~name:(id "items")
              ~columns:[ column "second"; column "first" ]
              ()
          ]
      in
      let query =
        Sql.parse "DELETE FROM items AS i RETURNING i.*"
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      let value =
        Statement_plan.create schema query
        |> Result.map_error ~f:Sql.error_to_string
        |> Result.ok_or_failwith
      in
      assert (
        List.equal
          String.equal
          (List.map (Statement_plan.fields value) ~f:(fun field -> field.name))
          [ "second"; "first" ])
    ;;

    let%test "JSON writes do not require an equality operator" =
      Result.is_ok (compile "UPDATE items SET document = $document")
    ;;

    let%test "JSON predicates still require an equality operator" =
      Result.is_error (compile "UPDATE items SET name = $name WHERE document = $document")
    ;;

    let%test "UPDATE DEFAULT accepts unsupported unused column types" =
      Result.is_ok (compile "UPDATE items SET numbers = DEFAULT RETURNING id")
    ;;

    let%test "DO NOTHING can omit its conflict target" =
      Result.is_ok (compile "INSERT INTO items (id) VALUES ($id) ON CONFLICT DO NOTHING")
    ;;

    let%test "DO NOTHING accepts a unique column key" =
      Result.is_ok
        (compile "INSERT INTO items (name) VALUES ($name) ON CONFLICT (name) DO NOTHING")
    ;;

    let%test "matching native types permit EXCLUDED assignments" =
      Result.is_ok
        (compile
           "INSERT INTO items (id) VALUES ($id) ON CONFLICT (tenant, id) DO UPDATE SET tenant = EXCLUDED.id")
    ;;

    let%test "EXCLUDED requires exact types even when codecs match" =
      Result.is_error
        (compile
           "INSERT INTO items (id) VALUES ($id) ON CONFLICT (tenant, id) DO UPDATE SET name = EXCLUDED.short_name")
    ;;

    let%expect_test "EXCLUDED cannot supply an incompatible native type" =
      print_error
        "INSERT INTO items (id) VALUES ($id) ON CONFLICT (tenant, id) DO UPDATE SET name = EXCLUDED.id";
      [%expect
        {| SQL byte 82: EXCLUDED assignment requires identical native types; implicit casts are unsupported |}]
    ;;

    let%expect_test "INSERT target columns are unique" =
      print_error "INSERT INTO items (id, id) VALUES ($first, $second)";
      [%expect {| SQL byte 23: duplicate target column: id |}]
    ;;

    let%expect_test "VALUES row lengths match target columns" =
      print_error "INSERT INTO items (id, name) VALUES ($id), ($id, $name)";
      [%expect {| SQL byte 37: VALUES row length does not match INSERT columns |}]
    ;;

    let%expect_test "conflict target must be a recorded complete key" =
      print_error "INSERT INTO items (id) VALUES ($id) ON CONFLICT (id) DO NOTHING";
      [%expect
        {| SQL byte 49: conflict columns do not match a primary or unique key in the snapshot |}]
    ;;

    let%test "conflict columns are unique" =
      Result.is_error
        (compile "INSERT INTO items (id) VALUES ($id) ON CONFLICT (id, id) DO NOTHING")
    ;;

    let%test "unknown INSERT column is rejected" =
      Result.is_error (compile "INSERT INTO items (missing) VALUES (DEFAULT)")
    ;;

    let%test "unknown EXCLUDED column is rejected" =
      Result.is_error
        (compile
           "INSERT INTO items (id) VALUES ($id) ON CONFLICT (tenant, id) DO UPDATE SET id = EXCLUDED.missing")
    ;;

    let%test "DO UPDATE requires a conflict target" =
      Result.is_error
        (compile
           "INSERT INTO items (id) VALUES ($id) ON CONFLICT DO UPDATE SET name = DEFAULT")
    ;;

    let%test "UPDATE assignments cannot duplicate their target" =
      Result.is_error (compile "UPDATE items SET id = $id, id = DEFAULT")
    ;;

    let%test "UPDATE target columns cannot be qualified" =
      Result.is_error (compile "UPDATE items i SET i.id = $id")
    ;;

    let%test "target aliases hide the table name in RETURNING" =
      Result.is_error (compile "DELETE FROM items i RETURNING items.id")
    ;;

    let%test "EXCLUDED is not available in RETURNING" =
      Result.is_error
        (compile
           "INSERT INTO items (id) VALUES ($id) ON CONFLICT DO NOTHING RETURNING EXCLUDED.id")
    ;;

    let%test "EXCLUDED is not available in ordinary WHERE" =
      Result.is_error (compile "DELETE FROM items WHERE EXCLUDED.id = $id")
    ;;

    let%test "EXCLUDED requires a distinct target alias" =
      Result.is_error
        (compile
           "INSERT INTO items AS excluded (id) VALUES ($id) ON CONFLICT (tenant, id) DO UPDATE SET id = EXCLUDED.id")
    ;;

    let%test "VALUES requires an explicit column list" =
      Result.is_error (compile "INSERT INTO items VALUES ($id)")
    ;;

    let%test "multiple DML statements are rejected" =
      Result.is_error (compile "DELETE FROM items; DELETE FROM items")
    ;;

    let%test "ON CONSTRAINT remains unsupported" =
      Result.is_error
        (compile
           "INSERT INTO items (id) VALUES ($id) ON CONFLICT ON CONSTRAINT key DO NOTHING")
    ;;

    let%test "partial conflict targets remain unsupported" =
      Result.is_error
        (compile
           "INSERT INTO items (id) VALUES ($id) ON CONFLICT (id) WHERE id = $id DO NOTHING")
    ;;

    let%test "INSERT SELECT is supported" =
      Result.is_ok (compile "INSERT INTO items (id) SELECT id FROM items")
    ;;

    let%test "UPDATE FROM is supported" =
      Result.is_ok (compile "UPDATE items SET id = $id FROM items other")
    ;;

    let%test "DELETE USING is supported" =
      Result.is_ok (compile "DELETE FROM items USING items other")
    ;;

    let%test "SQL literals is supported" =
      Result.is_ok (compile "INSERT INTO items (id) VALUES (1)")
    ;;

    let%test_unit "quoted names and comments preserve SQL text" =
      let value =
        plan
          "/* insert */ INSERT INTO \"public\".\"items\" AS \"i\" (\"id\") VALUES (${1l}) RETURNING \"i\".\"id\" AS \"identifier\";"
      in
      assert (
        String.equal
          value.sql
          "/* insert */ INSERT INTO \"public\".\"items\" AS \"i\" (\"id\") VALUES ($1) RETURNING \"i\".\"id\" AS \"identifier\";");
      assert (String.equal (List.hd_exn (Statement_plan.fields value)).name "identifier")
    ;;
  end)
;;
