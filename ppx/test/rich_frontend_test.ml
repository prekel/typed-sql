open! Base
open Typed_sql_pgocaml_ppx

let%test_module "nested PostgreSQL frontend" =
  (module struct
    let schema =
      let channel = Stdlib.open_in_bin "schema.json" in
      let text =
        Exn.protect
          ~f:(fun () ->
            Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
          ~finally:(fun () -> Stdlib.close_in_noerr channel)
      in
      Typed_sql_schema.Schema_snapshot.of_string text
      |> Result.map_error ~f:Typed_sql_schema.Schema_snapshot.error_to_string
      |> Result.ok_or_failwith
    ;;

    let compile sql =
      let open Result.Let_syntax in
      let%bind query = Sql.parse sql in
      Statement_plan.create schema query
    ;;

    let plan sql =
      compile sql |> Result.map_error ~f:Sql.error_to_string |> Result.ok_or_failwith
    ;;

    let fields sql = Statement_plan.fields (plan sql)

    let%test "left outer join" =
      Result.is_ok
        (compile
           {sql|SELECT p.id, l.label FROM join_people p LEFT OUTER JOIN join_links l ON p.id = l.person_id|sql})
    ;;

    let%test "right outer join" =
      Result.is_ok
        (compile
           {sql|SELECT p.id, l.label FROM join_people p RIGHT OUTER JOIN join_links l ON p.id = l.person_id|sql})
    ;;

    let%test "full outer join" =
      Result.is_ok
        (compile
           {sql|SELECT p.id, l.label FROM join_people p FULL OUTER JOIN join_links l ON p.id = l.person_id|sql})
    ;;

    let%test "cross join" =
      Result.is_ok
        (compile {sql|SELECT p.name FROM join_people p CROSS JOIN join_links l|sql})
    ;;

    let%test "comma precedence" =
      Result.is_ok
        (compile
           {sql|SELECT p.name FROM join_people p, join_links l JOIN join_people other ON other.id = l.person_id|sql})
    ;;

    let%test "group alias" =
      Result.is_ok
        (compile
           {sql|SELECT g.name FROM (join_people p JOIN join_links l ON p.id = l.person_id) AS g|sql})
    ;;

    let%test "using column" =
      Result.is_ok
        (compile {sql|SELECT id FROM join_people p FULL JOIN join_links l USING (id)|sql})
    ;;

    let%test "natural join" =
      Result.is_ok
        (compile {sql|SELECT id FROM join_people p NATURAL LEFT JOIN join_links l|sql})
    ;;

    let%test "arithmetic precedence" =
      Result.is_ok (compile {sql|SELECT id+1*2 AS next FROM join_people|sql})
    ;;

    let%test "cast syntax" =
      Result.is_ok
        (compile {sql|SELECT CAST(id AS bigint), id::text FROM join_people|sql})
    ;;

    let%test "type modifiers" =
      Result.is_ok
        (compile {sql|SELECT name::varchar(10), id::numeric(12,2) FROM join_people|sql})
    ;;

    let%test "case expression" =
      Result.is_ok
        (compile
           {sql|SELECT CASE WHEN id > 1 THEN name ELSE 'none' END AS result FROM join_people|sql})
    ;;

    let%test "simple case" =
      Result.is_ok
        (compile
           {sql|SELECT CASE id WHEN 1 THEN name ELSE 'none' END FROM join_people|sql})
    ;;

    let%test "coalesce nullif" =
      Result.is_ok
        (compile {sql|SELECT COALESCE(note, 'none'), NULLIF(id, 0) FROM join_people|sql})
    ;;

    let%test "aggregate grouping" =
      Result.is_ok
        (compile
           {sql|SELECT p.name, count(l.id) AS n FROM join_people p LEFT JOIN join_links l ON p.id = l.person_id GROUP BY p.name HAVING count(l.id) >= $minimum ORDER BY n DESC|sql})
    ;;

    let%test "aggregate filter" =
      Result.is_ok
        (compile
           {sql|SELECT count(DISTINCT person_id) FILTER (WHERE active), array_agg(id ORDER BY id DESC), string_agg(label, $separator ORDER BY id) FROM join_links|sql})
    ;;

    let%test "group expressions" =
      Result.is_ok
        (compile {sql|SELECT id+1 AS next, count(*) FROM join_people GROUP BY id+1|sql})
    ;;

    let%test "group ordinal" =
      Result.is_ok
        (compile {sql|SELECT name, count(*) FROM join_people GROUP BY 1 ORDER BY 2|sql})
    ;;

    let%test "union types" =
      Result.is_ok
        (compile
           {sql|SELECT NULL AS n UNION ALL SELECT 1 UNION SELECT 2::bigint ORDER BY n LIMIT $limit|sql})
    ;;

    let%test "set precedence" =
      Result.is_ok
        (compile
           {sql|SELECT id FROM join_people UNION SELECT person_id FROM join_links INTERSECT SELECT id FROM join_people|sql})
    ;;

    let%test "scalar correlation" =
      Result.is_ok
        (compile
           {sql|SELECT p.name, (SELECT count(*) FROM join_links l WHERE l.person_id = p.id) AS n FROM join_people p|sql})
    ;;

    let%test "exists correlation" =
      Result.is_ok
        (compile
           {sql|SELECT name FROM join_people p WHERE EXISTS (SELECT id FROM join_links l WHERE l.person_id = p.id)|sql})
    ;;

    let%test "in subquery" =
      Result.is_ok
        (compile
           {sql|SELECT id FROM join_people WHERE id IN (SELECT person_id FROM join_links)|sql})
    ;;

    let%test "any subquery" =
      Result.is_ok
        (compile
           {sql|SELECT id FROM join_people WHERE id = ANY(SELECT person_id FROM join_links)|sql})
    ;;

    let%test "derived output" =
      Result.is_ok
        (compile {sql|SELECT q.n FROM (SELECT id+1 AS n FROM join_people) q|sql})
    ;;

    let%test "cte chain" =
      Result.is_ok
        (compile
           {sql|WITH first AS (SELECT id FROM join_people), second AS (SELECT id FROM first) SELECT id FROM second|sql})
    ;;

    let%test "cte aliases" =
      Result.is_ok
        (compile
           {sql|WITH t(n) AS NOT MATERIALIZED (SELECT id FROM join_people) SELECT n FROM t|sql})
    ;;

    let%test "recursive select" =
      Result.is_ok
        (compile
           {sql|WITH RECURSIVE t(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM t WHERE n < $maximum) SELECT n FROM t|sql})
    ;;

    let%test "recursive forward dependency" =
      Result.is_ok
        (compile
           {sql|WITH RECURSIVE first AS (SELECT id FROM second), second AS (SELECT id FROM join_people) SELECT id FROM first|sql})
    ;;

    let%test "dml cte returning" =
      Result.is_ok
        (compile
           {sql|WITH changed AS (UPDATE join_people SET name = name || $suffix WHERE id = $id RETURNING id, name) SELECT * FROM changed|sql})
    ;;

    let%test "dml cte effect" =
      Result.is_ok
        (compile
           {sql|WITH changed AS (DELETE FROM join_links WHERE id = $id) SELECT id FROM join_people|sql})
    ;;

    let%test "insert select" =
      Result.is_ok
        (compile
           {sql|INSERT INTO join_people (id, name) SELECT id + 100, name FROM join_people RETURNING id|sql})
    ;;

    let%test "move rows cte" =
      Result.is_ok
        (compile
           {sql|WITH moved AS (DELETE FROM join_people WHERE id = $id RETURNING id, name, note) INSERT INTO join_people SELECT * FROM moved RETURNING id|sql})
    ;;

    let%test "cte before command" =
      Result.is_ok
        (compile
           {sql|WITH gone AS (DELETE FROM join_links WHERE id = $id RETURNING person_id) DELETE FROM join_people WHERE id IN (SELECT person_id FROM gone)|sql})
    ;;

    let%test "join parenthesis hides members" =
      Result.is_error
        (compile
           {sql|SELECT p.id FROM (join_people p JOIN join_links l ON p.id = l.person_id) g|sql})
    ;;

    let%test "comma scope excludes earlier source from ON" =
      Result.is_error
        (compile
           {sql|SELECT p.name FROM join_people p, join_links l JOIN join_people other ON p.id = l.person_id|sql})
    ;;

    let%test "invalid CASE common type" =
      Result.is_error
        (compile
           {sql|SELECT CASE WHEN true THEN id ELSE active END FROM join_people p JOIN join_links l ON p.id = l.person_id|sql})
    ;;

    let%test "invalid bool sum" =
      Result.is_error (compile {sql|SELECT sum(active) FROM join_links|sql})
    ;;

    let%test "nested aggregate" =
      Result.is_error (compile {sql|SELECT sum(count(*)) FROM join_links|sql})
    ;;

    let%test "aggregate in where" =
      Result.is_error (compile {sql|SELECT id FROM join_people WHERE count(*) > 0|sql})
    ;;

    let%test "missing grouped column" =
      Result.is_error
        (compile {sql|SELECT name, count(*) FROM join_people GROUP BY id|sql})
    ;;

    let%test "set width" =
      Result.is_error
        (compile
           {sql|SELECT id, name FROM join_people UNION SELECT id FROM join_links|sql})
    ;;

    let%test "set type" =
      Result.is_error
        (compile {sql|SELECT name FROM join_people UNION SELECT id FROM join_links|sql})
    ;;

    let%test "pairwise unknown resolution" =
      Result.is_error (compile {sql|SELECT NULL UNION SELECT NULL UNION SELECT 1|sql})
    ;;

    let%test "scalar width" =
      Result.is_error (compile {sql|SELECT (SELECT id, name FROM join_people)|sql})
    ;;

    let%test "non-lateral correlation" =
      Result.is_error
        (compile
           {sql|SELECT q.n FROM join_people p JOIN (SELECT p.id AS n) q ON true|sql})
    ;;

    let%test "ordinary forward CTE reference" =
      Result.is_error
        (compile
           {sql|WITH first AS (SELECT id FROM second), second AS (SELECT id FROM join_people) SELECT id FROM first|sql})
    ;;

    let%test "mutual recursive CTE" =
      Result.is_error
        (compile
           {sql|WITH RECURSIVE a AS (SELECT id FROM b), b AS (SELECT id FROM a) SELECT id FROM a|sql})
    ;;

    let%test "recursive anchor self reference" =
      Result.is_error
        (compile
           {sql|WITH RECURSIVE t(n) AS (SELECT n FROM t UNION ALL SELECT n+1 FROM t) SELECT n FROM t|sql})
    ;;

    let%test "recursive type mismatch" =
      Result.is_error
        (compile
           {sql|WITH RECURSIVE t(n) AS (SELECT 1 UNION ALL SELECT n::bigint FROM t) SELECT n FROM t|sql})
    ;;

    let%test "recursive nullable join" =
      Result.is_error
        (compile
           {sql|WITH RECURSIVE t(n) AS (SELECT 1 UNION ALL SELECT t.n FROM join_people p LEFT JOIN t ON p.id = t.n) SELECT n FROM t|sql})
    ;;

    let%test "recursive aggregate" =
      Result.is_error
        (compile
           {sql|WITH RECURSIVE t(n) AS (SELECT 1::bigint UNION ALL SELECT count(*) FROM t) SELECT n FROM t|sql})
    ;;

    let%test "CTE without RETURNING is not a relation" =
      Result.is_error
        (compile {sql|WITH gone AS (DELETE FROM join_people) SELECT * FROM gone|sql})
    ;;

    let%test "nested data-modifying WITH" =
      Result.is_error
        (compile
           {sql|SELECT * FROM (WITH gone AS (DELETE FROM join_people RETURNING id) SELECT id FROM gone) q|sql})
    ;;

    let%test "recursive DML" =
      Result.is_error
        (compile
           {sql|WITH RECURSIVE gone AS (DELETE FROM join_people WHERE id IN (SELECT id FROM gone) RETURNING id) SELECT * FROM gone|sql})
    ;;

    let%test "unknown function" =
      Result.is_error (compile {sql|SELECT unknown_function(id) FROM join_people|sql})
    ;;

    let%test "unknown cast" =
      Result.is_error (compile {sql|SELECT id::unknown_type FROM join_people|sql})
    ;;

    let%test "unsupported window" =
      Result.is_error (compile {sql|SELECT count(*) OVER () FROM join_people|sql})
    ;;

    let%test_unit "computed outputs retain upstream optional codecs" =
      let result =
        fields "SELECT count(*), sum(id), avg(id), min(name) FROM join_people"
      in
      assert (
        List.equal
          String.equal
          (List.map result ~f:(fun field -> Codec.to_string field.Statement_plan.codec))
          [ "int64"; "int64"; "string"; "string" ]);
      assert (List.for_all result ~f:(fun field -> field.Statement_plan.nullable))
    ;;

    let%test_unit "direct outer join columns retain attribute nullability" =
      let result =
        fields
          "SELECT p.id, l.id, l.label FROM join_people p LEFT JOIN join_links l ON p.id = l.person_id"
      in
      assert (
        List.equal
          Bool.equal
          (List.map result ~f:(fun field -> field.Statement_plan.nullable))
          [ false; false; true ])
    ;;

    let%test_unit "FULL USING has no direct column origin" =
      let result = fields "SELECT id FROM join_people FULL JOIN join_links USING (id)" in
      assert (List.for_all result ~f:(fun field -> field.Statement_plan.nullable))
    ;;

    let%test_unit "nested placeholders remain in lexical SQL order" =
      let result =
        plan
          "WITH t AS (SELECT id FROM join_people WHERE id > $minimum) SELECT CASE WHEN id > $threshold THEN $yes ELSE $no END AS label FROM t WHERE id IN (SELECT person_id FROM join_links WHERE label = $?label) LIMIT $limit"
      in
      assert (
        List.equal
          String.equal
          (List.map result.parameters ~f:(fun p -> Codec.to_string p.Statement_plan.codec))
          [ "int32"; "int32"; "string"; "string"; "string"; "int64" ]);
      assert (
        String.equal
          result.sql
          "WITH t AS (SELECT id FROM join_people WHERE id > $1) SELECT CASE WHEN id > $2 THEN $3 ELSE $4 END AS label FROM t WHERE id IN (SELECT person_id FROM join_links WHERE label = $5) LIMIT $6")
    ;;

    let%test "parenthesized relation retains its inner alias" =
      Result.is_ok
        (compile
           "SELECT p.id FROM (join_people p) JOIN join_links l ON p.id = l.person_id")
    ;;

    let%test "nonrecursive CTE can read a base table with the same name" =
      Result.is_ok
        (compile
           "WITH join_people AS (SELECT id FROM join_people) SELECT id FROM join_people")
    ;;

    let%test "grouping rejects an aggregate output position" =
      Result.is_error (compile "SELECT count(*) FROM join_people GROUP BY 1")
    ;;

    let%test "grouping rejects an aggregate output alias" =
      Result.is_error (compile "SELECT count(*) AS n FROM join_people GROUP BY n")
    ;;

    let%test "grouping allows a no-op integer cast" =
      Result.is_ok (compile "SELECT id FROM join_people GROUP BY id::integer")
    ;;

    let%test "correlated subqueries cannot read ungrouped outer columns" =
      Result.is_error
        (compile
           "SELECT p.name, (SELECT count(*) FROM join_links l WHERE l.person_id = p.id) FROM join_people p GROUP BY p.name")
    ;;

    let%test "correlated subqueries can read grouped outer columns" =
      Result.is_ok
        (compile
           "SELECT p.id, (SELECT count(*) FROM join_links l WHERE l.person_id = p.id) FROM join_people p GROUP BY p.id")
    ;;

    let%test "aggregates attached to an outer level are diagnosed" =
      Result.is_error (compile "SELECT (SELECT sum(p.id)) FROM join_people p")
    ;;

    let%test "RETURNING cannot contain a local aggregate" =
      Result.is_error (compile "UPDATE join_people SET id = id+1 RETURNING count(*)")
    ;;

    let%test "INSERT VALUES cannot read the target row" =
      Result.is_error (compile "INSERT INTO join_people (id, name) VALUES (id+1, 'bad')")
    ;;

    let%test "UPDATE RETURNING cannot acquire ORDER BY" =
      Result.is_error
        (compile "UPDATE join_people SET id = id+1 RETURNING id ORDER BY id")
    ;;

    let%test "MIN has no jsonb overload" =
      Result.is_error (compile "SELECT min(binary_document) FROM people")
    ;;

    let%test "floating remainder is rejected" =
      Result.is_error (compile "SELECT real_value % 2 FROM people")
    ;;

    let%test "INNER OUTER JOIN is invalid" =
      Result.is_error
        (compile "SELECT p.id FROM join_people p INNER OUTER JOIN join_links l ON true")
    ;;

    let%test "NATURAL CROSS JOIN is invalid" =
      Result.is_error
        (compile "SELECT p.id FROM join_people p NATURAL CROSS JOIN join_links l")
    ;;

    let%test "modifier-sensitive cast origin is not guessed" =
      Result.is_error (compile "SELECT fixed_value::char(3) FROM people")
    ;;

    let%test_unit "NULLIF follows numeric operator promotion" =
      let result = fields "SELECT NULLIF(id, 2.2) FROM join_people" in
      assert (
        List.equal
          String.equal
          (List.map result ~f:(fun field -> Codec.to_string field.Statement_plan.codec))
          [ "string" ])
    ;;

    let%test_unit "outer casts do not alter COALESCE parameter inference" =
      let result = plan "SELECT COALESCE($id, id)::bigint FROM join_people" in
      assert (
        List.equal
          String.equal
          (List.map result.parameters ~f:(fun parameter ->
             Codec.to_string parameter.Statement_plan.codec))
          [ "int32" ])
    ;;

    let%test_unit "simple CASE input can be explicitly typed" =
      let result =
        plan "SELECT CASE $id::integer WHEN id THEN 'yes' ELSE 'no' END FROM join_people"
      in
      assert (
        List.equal
          String.equal
          (List.map result.parameters ~f:(fun parameter ->
             Codec.to_string parameter.Statement_plan.codec))
          [ "int32" ])
    ;;

    let%test_unit "parenthesized query tails retain all parameters" =
      let result =
        plan
          "(SELECT id FROM join_people WHERE id > $minimum LIMIT $inner) UNION ALL (SELECT id FROM join_people LIMIT $other) LIMIT $outer"
      in
      assert (
        List.equal
          String.equal
          (List.map result.parameters ~f:(fun parameter ->
             Codec.to_string parameter.Statement_plan.codec))
          [ "int32"; "int64"; "int64"; "int64" ]);
      assert (
        String.equal
          result.sql
          "(SELECT id FROM join_people WHERE id > $1 LIMIT $2) UNION ALL (SELECT id FROM join_people LIMIT $3) LIMIT $4")
    ;;

    let%test_unit "output names follow casts and scalar subqueries" =
      let result =
        fields "SELECT 1::bigint, CASE WHEN true THEN name ELSE name END FROM join_people"
      in
      assert (
        List.equal
          String.equal
          (List.map result ~f:(fun field -> field.Statement_plan.name))
          [ "int8"; "name" ])
    ;;

    let%test "untyped simple CASE input follows PostgreSQL text default" =
      Result.is_error
        (compile "SELECT CASE $id WHEN id THEN 'yes' ELSE 'no' END FROM join_people")
    ;;
  end)
;;
