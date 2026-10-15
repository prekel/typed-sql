open! Base
open Typed_sql_pgocaml_ppx

let%test_module "table functions and primary key grouping" =
  (module struct
    let schema =
      let channel = Stdlib.open_in_bin "schema.json" in
      let source =
        Exn.protect
          ~finally:(fun () -> Stdlib.close_in_noerr channel)
          ~f:(fun () ->
            Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
      in
      Typed_sql_schema.Schema_snapshot.of_string source
      |> Result.map_error ~f:Typed_sql_schema.Schema_snapshot.error_to_string
      |> Result.ok_or_failwith
    ;;

    let compile_with schema sql =
      let open Result.Let_syntax in
      let%bind query = Sql.parse sql in
      Statement_plan.create schema query
    ;;

    let compile = compile_with schema

    let plan sql =
      compile sql |> Result.map_error ~f:Sql.error_to_string |> Result.ok_or_failwith
    ;;

    let%test_unit "unnest alias" =
      ignore (plan {sql|SELECT u FROM unnest($ids::integer[]) u|sql} : Statement_plan.t)
    ;;

    let%test_unit "unnest ordinality" =
      ignore
        (plan {sql|SELECT * FROM unnest($ids::integer[]) WITH ORDINALITY|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "multi unnest" =
      ignore
        (plan
           {sql|SELECT a,b,n FROM unnest($ids::integer[],$names::text[]) WITH ORDINALITY AS u(a,b,n)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "implicit lateral" =
      ignore
        (plan {sql|SELECT u FROM native_items n, unnest(n.numbers) u|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "left lateral" =
      ignore
        (plan
           {sql|SELECT u FROM native_items n LEFT JOIN LATERAL unnest(n.numbers) u ON true|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "series type from step" =
      ignore
        (plan {sql|SELECT * FROM generate_series($start,$stop,1)|sql} : Statement_plan.t)
    ;;

    let%test_unit "series integer" =
      ignore
        (plan {sql|SELECT * FROM generate_series(1,$stop,$step)|sql} : Statement_plan.t)
    ;;

    let%test_unit "series bigint" =
      ignore
        (plan {sql|SELECT * FROM generate_series(1::bigint,$stop)|sql} : Statement_plan.t)
    ;;

    let%test_unit "series numeric" =
      ignore
        (plan {sql|SELECT * FROM generate_series(1::numeric,$stop,$step)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "series temporal" =
      ignore
        (plan {sql|SELECT * FROM generate_series($start::timestamp,$stop,$step)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "series timestamptz" =
      ignore
        (plan
           {sql|SELECT * FROM pg_catalog.generate_series($start::timestamptz,$stop,$step)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "array functions" =
      ignore
        (plan
           {sql|SELECT cardinality(numbers), array_length(numbers,$dimension),array_to_string(numbers,$delimiter,$replacement) FROM native_items|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "domain array" =
      ignore
        (plan {sql|SELECT * FROM unnest($values::public.nested_native[]) u|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "group dependency" =
      ignore
        (plan {sql|SELECT * FROM group_keys GROUP BY tenant,id|sql} : Statement_plan.t)
    ;;

    let%test_unit "group dependency having order" =
      ignore
        (plan
           {sql|SELECT name,count(*) FROM group_keys GROUP BY tenant,id HAVING name<>'' ORDER BY name|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "group self join" =
      ignore
        (plan
           {sql|SELECT a.name,b.name FROM group_keys a JOIN group_keys b ON a.id=b.id GROUP BY a.tenant,a.id,b.tenant,b.id|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "group subquery correlation" =
      ignore
        (plan {sql|SELECT (SELECT k.name) FROM group_keys k GROUP BY k.tenant,k.id|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "update from function" =
      ignore
        (plan
           {sql|UPDATE group_keys SET name='x' FROM generate_series(1,2) g WHERE id=g RETURNING id|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "delete using function" =
      ignore
        (plan
           {sql|DELETE FROM group_keys USING generate_series(1,2) g WHERE id=g RETURNING id|sql}
         : Statement_plan.t)
    ;;

    let%test "unknown array" =
      Result.is_error (compile {sql|SELECT * FROM unnest($ids) u|sql})
    ;;

    let%test "non array" = Result.is_error (compile {sql|SELECT * FROM unnest(1) u|sql})

    let%test "smallint series is ambiguous" =
      Result.is_error
        (compile {sql|SELECT * FROM generate_series(1::smallint,3::smallint)|sql})
    ;;

    let%test_unit "temporal mixed overload" =
      ignore
        (plan
           {sql|SELECT * FROM generate_series($start::timestamp,$stop::timestamptz,$step::interval)|sql}
         : Statement_plan.t)
    ;;

    let%test "unknown series" =
      Result.is_error (compile {sql|SELECT * FROM generate_series($start,$stop) g|sql})
    ;;

    let%test "float series" =
      Result.is_error
        (compile {sql|SELECT * FROM generate_series(1::float8,2::float8) g|sql})
    ;;

    let%test "missing temporal step" =
      Result.is_error
        (compile {sql|SELECT * FROM generate_series($start::timestamp,$stop) g|sql})
    ;;

    let%test "bad temporal step" =
      Result.is_error
        (compile {sql|SELECT * FROM generate_series($start::timestamp,$stop,1) g|sql})
    ;;

    let%test "bad array dimension" =
      Result.is_error
        (compile {sql|SELECT array_length(numbers,'x'::text) FROM native_items|sql})
    ;;

    let%test "bad delimiter" =
      Result.is_error
        (compile {sql|SELECT array_to_string(numbers,1) FROM native_items|sql})
    ;;

    let%test "unknown cardinality" =
      Result.is_error (compile {sql|SELECT cardinality($values)|sql})
    ;;

    let%test "scalar srf" =
      Result.is_error (compile {sql|SELECT unnest(numbers) FROM native_items|sql})
    ;;

    let%test "rows from" =
      Result.is_error (compile {sql|SELECT * FROM ROWS FROM(unnest($ids::int[])) u|sql})
    ;;

    let%test "right correlation" =
      Result.is_error
        (compile
           {sql|SELECT u FROM native_items n RIGHT JOIN unnest(n.numbers) u ON true|sql})
    ;;

    let%test "forward reference" =
      Result.is_error (compile {sql|SELECT u FROM unnest(n.numbers) u,native_items n|sql})
    ;;

    let%test "aggregate in function" =
      Result.is_error
        (compile {sql|SELECT * FROM generate_series(count(*)::integer,3) g|sql})
    ;;

    let%test "window in function" =
      Result.is_error
        (compile
           {sql|SELECT * FROM generate_series(row_number() OVER()::integer,3) g|sql})
    ;;

    let%test "function modifiers" =
      Result.is_error (compile {sql|SELECT * FROM unnest(DISTINCT $ids::int[]) u|sql})
    ;;

    let%test "custom namespace" =
      Result.is_error (compile {sql|SELECT * FROM public.generate_series(1,3) g|sql})
    ;;

    let%test "multi qualified unnest" =
      Result.is_error
        (compile {sql|SELECT * FROM pg_catalog.unnest($ids::int[],$names::text[]) u|sql})
    ;;

    let%test "incomplete primary key" =
      Result.is_error (compile {sql|SELECT name FROM group_keys GROUP BY id|sql})
    ;;

    let%test "deferrable key" =
      Result.is_error
        (compile {sql|SELECT name FROM deferrable_group_keys GROUP BY tenant,id|sql})
    ;;

    let%test "derived key" =
      Result.is_error
        (compile
           {sql|SELECT name FROM (SELECT * FROM group_keys) k GROUP BY tenant,id|sql})
    ;;

    let%test "cte key" =
      Result.is_error
        (compile
           {sql|WITH k AS(SELECT * FROM group_keys) SELECT name FROM k GROUP BY tenant,id|sql})
    ;;

    let%test "self join key mismatch" =
      Result.is_error
        (compile
           {sql|SELECT b.name FROM group_keys a JOIN group_keys b ON a.id=b.id GROUP BY a.tenant,a.id|sql})
    ;;

    let%test "unique is not primary" =
      Result.is_error (compile {sql|SELECT id FROM ppx_items GROUP BY name|sql})
    ;;

    let%test_unit "missing PK deferrability requests a fresh snapshot" =
      let module S = Typed_sql_schema.Schema_ir in
      let legacy =
        S.v
          (List.map (S.tables schema) ~f:(fun table ->
             S.table
               ?schema:(S.table_schema table)
               ~name:(S.table_name table)
               ~columns:(S.columns table)
               ()))
      in
      match compile_with legacy "SELECT name FROM group_keys GROUP BY tenant,id" with
      | Error error ->
        assert (
          String.is_substring
            (Sql.error_to_string error)
            ~substring:"refresh the schema snapshot")
      | Ok _ -> failwith "missing metadata accepted"
    ;;

    let%test_unit "function outputs have upstream computed nullability" =
      let fields =
        Statement_plan.fields
          (plan "SELECT * FROM unnest($ids::int[]) WITH ORDINALITY u(value,n)")
      in
      assert (
        List.equal
          String.equal
          (List.map fields ~f:(fun f -> f.Statement_plan.name))
          [ "value"; "n" ]);
      assert (List.for_all fields ~f:(fun field -> field.Statement_plan.nullable))
    ;;
  end)
;;
