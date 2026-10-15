open! Base
open Typed_sql_pgocaml_ppx

let%test_module "SELECT SRF and ROWS FROM" =
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

    let%test "rows remains a table identifier" =
      Result.is_ok (Sql.parse "SELECT * FROM rows")
    ;;

    let%test_unit "simple SELECT SRF" =
      ignore (plan {sql|SELECT generate_series(1,3)|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT unnest" =
      ignore (plan {sql|SELECT unnest($ids::int[])|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT qualified SRF" =
      ignore (plan {sql|SELECT pg_catalog.unnest($ids::int[])|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT scalar wrapper" =
      ignore (plan {sql|SELECT abs(generate_series(-2,2))+1|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT nested SRF" =
      ignore
        (plan {sql|SELECT generate_series(1,generate_series(1,3))|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT multiple SRFs" =
      ignore
        (plan {sql|SELECT generate_series(1,3),unnest($names::text[])|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "SELECT NULLIF wrapper" =
      ignore (plan {sql|SELECT nullif(generate_series(1,3),2)|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT comparison" =
      ignore (plan {sql|SELECT generate_series(1,3) IN(1,3)|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT null test" =
      ignore (plan {sql|SELECT generate_series(1,3) IS NULL|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT quantifier" =
      ignore
        (plan {sql|SELECT generate_series(1,3)=ANY($ids::int[])|sql} : Statement_plan.t)
    ;;

    let%test_unit "SELECT aggregate input" =
      ignore
        (plan {sql|SELECT unnest(array_agg(id ORDER BY id)) FROM group_keys|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "SELECT window input" =
      ignore
        (plan
           {sql|SELECT generate_series(1,row_number() OVER(ORDER BY id)::int) FROM group_keys|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "GROUP BY SRF expression" =
      ignore
        (plan
           {sql|SELECT generate_series(1,3),count(*) FROM group_keys GROUP BY generate_series(1,3)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "GROUP BY SRF alias" =
      ignore
        (plan
           {sql|SELECT generate_series(1,3) AS n,count(*) FROM group_keys GROUP BY n|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ORDER BY SRF" =
      ignore
        (plan {sql|SELECT id FROM group_keys ORDER BY generate_series(1,2),id|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "SELECT SRF pagination" =
      ignore
        (plan
           {sql|SELECT generate_series(1,3) AS n ORDER BY n LIMIT $limit OFFSET $offset|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "SELECT SRF DISTINCT" =
      ignore
        (plan {sql|SELECT DISTINCT generate_series(1,3) AS n ORDER BY n|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "SRF CTE set operation" =
      ignore
        (plan
           {sql|WITH q AS(SELECT generate_series(1,2) AS n) SELECT n FROM q UNION ALL SELECT generate_series(3,3) ORDER BY n|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "INSERT SELECT SRF" =
      ignore
        (plan
           {sql|INSERT INTO group_keys(tenant,id,name) SELECT 1,generate_series(10,11),'n' RETURNING id|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "scalar subquery scope" =
      ignore
        (plan {sql|SELECT coalesce((SELECT generate_series(1,1)),0)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM implicit alias" =
      ignore
        (plan
           {sql|SELECT generate_series.generate_series,generate_series.unnest FROM ROWS FROM(generate_series(1,2),unnest($ids::int[]))|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM alias" =
      ignore
        (plan {sql|SELECT q.q FROM ROWS FROM(generate_series(1,2)) q|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM aliases ordinality" =
      ignore
        (plan
           {sql|SELECT * FROM ROWS FROM(generate_series(1,2),unnest($names::text[])) WITH ORDINALITY q(id,name,n)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM multi array unnest" =
      ignore
        (plan
           {sql|SELECT * FROM ROWS FROM(unnest($ids::int[],$names::text[]),generate_series(1,2)) q(id,name,n)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM scalar function" =
      ignore
        (plan
           {sql|SELECT * FROM ROWS FROM(lower($name),generate_series(1,2)) q(label,n)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM lateral" =
      ignore
        (plan
           {sql|SELECT * FROM group_keys k LEFT JOIN LATERAL ROWS FROM(generate_series(1,k.id),unnest($ids::int[])) q(n,id) ON true|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM comma" =
      ignore
        (plan
           {sql|SELECT q.n FROM group_keys k, ROWS FROM(generate_series(1,k.id)) q(n)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ROWS FROM DML" =
      ignore
        (plan
           {sql|DELETE FROM group_keys USING ROWS FROM(generate_series(1,2)) q(id) WHERE group_keys.id=q.id RETURNING group_keys.id|sql}
         : Statement_plan.t)
    ;;

    let%test "SRF WHERE" =
      Result.is_error
        (compile {sql|SELECT id FROM group_keys WHERE generate_series(1,3)=id|sql})
    ;;

    let%test "SRF HAVING" =
      Result.is_error
        (compile {sql|SELECT count(*) FROM group_keys HAVING generate_series(1,3)>0|sql})
    ;;

    let%test "SRF JOIN ON" =
      Result.is_error
        (compile
           {sql|SELECT k.id FROM group_keys k JOIN group_keys b ON generate_series(1,3)=k.id|sql})
    ;;

    let%test "SRF LIMIT" =
      Result.is_error
        (compile {sql|SELECT id FROM group_keys LIMIT generate_series(1,3)|sql})
    ;;

    let%test "SRF OFFSET" =
      Result.is_error
        (compile {sql|SELECT id FROM group_keys OFFSET generate_series(1,3)|sql})
    ;;

    let%test "SRF RETURNING" =
      Result.is_error
        (compile {sql|DELETE FROM group_keys RETURNING generate_series(1,3)|sql})
    ;;

    let%test "SRF UPDATE SET" =
      Result.is_error (compile {sql|UPDATE group_keys SET id=generate_series(1,3)|sql})
    ;;

    let%test "SRF INSERT VALUES" =
      Result.is_error
        (compile
           {sql|INSERT INTO group_keys(tenant,id,name) VALUES(1,generate_series(1,3),'n')|sql})
    ;;

    let%test "SRF COALESCE" =
      Result.is_error (compile {sql|SELECT coalesce(generate_series(1,3),0)|sql})
    ;;

    let%test "SRF CASE" =
      Result.is_error
        (compile {sql|SELECT CASE WHEN true THEN generate_series(1,3) ELSE 0 END|sql})
    ;;

    let%test "SRF CASE condition" =
      Result.is_error
        (compile {sql|SELECT CASE WHEN generate_series(1,3)>0 THEN 1 END|sql})
    ;;

    let%test "SRF CASE operand" =
      Result.is_error
        (compile {sql|SELECT CASE generate_series(1,3) WHEN 1 THEN 2 END|sql})
    ;;

    let%test "SRF AND" =
      Result.is_error (compile {sql|SELECT generate_series(1,3)>0 AND true|sql})
    ;;

    let%test "SRF OR" =
      Result.is_error (compile {sql|SELECT false OR generate_series(1,3)>0|sql})
    ;;

    let%test "SRF NOT" =
      Result.is_error (compile {sql|SELECT NOT(generate_series(1,3)>0)|sql})
    ;;

    let%test "SRF BETWEEN" =
      Result.is_error (compile {sql|SELECT generate_series(1,3) BETWEEN 1 AND 3|sql})
    ;;

    let%test "SRF IN subquery" =
      Result.is_error (compile {sql|SELECT generate_series(1,3) IN(SELECT 1)|sql})
    ;;

    let%test "SRF ANY subquery" =
      Result.is_error (compile {sql|SELECT generate_series(1,3)=ANY(SELECT 1)|sql})
    ;;

    let%test "SRF variable IN list" =
      Result.is_error
        (compile {sql|SELECT generate_series(1,3) IN(id,1) FROM group_keys|sql})
    ;;

    let%test "SRF aggregate argument" =
      Result.is_error (compile {sql|SELECT sum(generate_series(1,3))|sql})
    ;;

    let%test "SRF aggregate ORDER BY" =
      Result.is_error
        (compile
           {sql|SELECT array_agg(id ORDER BY generate_series(1,3)) FROM group_keys|sql})
    ;;

    let%test "SRF aggregate FILTER" =
      Result.is_error
        (compile
           {sql|SELECT count(*) FILTER(WHERE generate_series(1,3)>0) FROM group_keys|sql})
    ;;

    let%test "SRF window argument" =
      Result.is_error (compile {sql|SELECT first_value(generate_series(1,3)) OVER()|sql})
    ;;

    let%test "SRF window partition" =
      Result.is_error
        (compile {sql|SELECT count(*) OVER(PARTITION BY generate_series(1,3))|sql})
    ;;

    let%test "SRF window ordering" =
      Result.is_error
        (compile {sql|SELECT count(*) OVER(ORDER BY generate_series(1,3))|sql})
    ;;

    let%test "SRF window frame" =
      Result.is_error
        (compile {sql|SELECT count(*) OVER(ROWS generate_series(1,3) PRECEDING)|sql})
    ;;

    let%test "SELECT multi array unnest" =
      Result.is_error (compile {sql|SELECT unnest($ids::int[],$names::text[])|sql})
    ;;

    let%test "SELECT unknown unnest" =
      Result.is_error (compile {sql|SELECT unnest($ids)|sql})
    ;;

    let%test "SELECT unknown series" =
      Result.is_error (compile {sql|SELECT generate_series($start,$stop)|sql})
    ;;

    let%test "SELECT SRF modifiers" =
      Result.is_error (compile {sql|SELECT generate_series(DISTINCT 1,3)|sql})
    ;;

    let%test "SELECT SRF OVER" =
      Result.is_error (compile {sql|SELECT generate_series(1,3) OVER()|sql})
    ;;

    let%test "ROWS FROM nested SRF" =
      Result.is_error
        (compile
           {sql|SELECT * FROM ROWS FROM(generate_series(1,generate_series(1,3))) q|sql})
    ;;

    let%test "ROWS FROM nested scalar" =
      Result.is_error
        (compile {sql|SELECT * FROM ROWS FROM(abs(generate_series(1,3))) q|sql})
    ;;

    let%test "ROWS FROM empty" =
      Result.is_error (compile {sql|SELECT * FROM ROWS FROM() q|sql})
    ;;

    let%test "ROWS FROM non function" =
      Result.is_error (compile {sql|SELECT * FROM ROWS FROM(1) q|sql})
    ;;

    let%test "ROWS FROM alias overflow" =
      Result.is_error
        (compile {sql|SELECT * FROM ROWS FROM(generate_series(1,3)) q(a,b)|sql})
    ;;

    let%test "ROWS FROM own output invisible" =
      Result.is_error
        (compile
           {sql|SELECT * FROM ROWS FROM(generate_series(1,2),generate_series(1,generate_series)) q|sql})
    ;;

    let%test "ROWS FROM forward reference" =
      Result.is_error
        (compile
           {sql|SELECT * FROM ROWS FROM(generate_series(1,k.id)) q,group_keys k|sql})
    ;;

    let%test "ROWS FROM RIGHT correlation" =
      Result.is_error
        (compile
           {sql|SELECT * FROM group_keys k RIGHT JOIN ROWS FROM(generate_series(1,k.id)) q ON true|sql})
    ;;

    let%test "ROWS FROM record definition" =
      Result.is_error
        (compile {sql|SELECT * FROM ROWS FROM(generate_series(1,2) AS(n int)) q|sql})
    ;;

    let%test "ROWS FROM unknown function" =
      Result.is_error (compile {sql|SELECT * FROM ROWS FROM(public.fn(1)) q|sql})
    ;;

    let%test "ungrouped SRF input" =
      Result.is_error
        (compile {sql|SELECT generate_series(1,id),count(*) FROM group_keys|sql})
    ;;

    let%test "SELECT DISTINCT hidden SRF ordering" =
      Result.is_error
        (compile
           {sql|SELECT DISTINCT id FROM group_keys ORDER BY generate_series(1,2)|sql})
    ;;

    let%test_unit "ROWS FROM field order and computed nullability" =
      let fields =
        Statement_plan.fields
          (plan
             "SELECT * FROM ROWS FROM(unnest($ids::int[]),generate_series(1,3)) WITH ORDINALITY q(id,value,n)")
      in
      assert (
        List.equal
          String.equal
          (List.map fields ~f:(fun f -> f.Statement_plan.name))
          [ "id"; "value"; "n" ]);
      assert (List.for_all fields ~f:(fun f -> f.Statement_plan.nullable))
    ;;

    let%test_unit "SELECT retains direct column nullability next to SRF" =
      let fields =
        Statement_plan.fields (plan "SELECT id,generate_series(1,3) AS n FROM group_keys")
      in
      assert (
        List.equal
          Bool.equal
          (List.map fields ~f:(fun f -> f.Statement_plan.nullable))
          [ false; true ])
    ;;
  end)
;;
