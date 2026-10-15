open! Base
open Typed_sql_pgocaml_ppx

let%test_module "PostgreSQL compatibility extensions" =
  (module struct
    let schema =
      let channel = Stdlib.open_in_bin "schema.json" in
      let text =
        Exn.protect
          ~finally:(fun () -> Stdlib.close_in_noerr channel)
          ~f:(fun () ->
            Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
      in
      Typed_sql_schema.Schema_snapshot.of_string text
      |> Result.map_error ~f:Typed_sql_schema.Schema_snapshot.error_to_string
      |> Result.ok_or_failwith
    ;;

    let compile sql =
      let open Result.Let_syntax in
      let%bind parsed = Sql.parse sql in
      Statement_plan.create schema parsed
    ;;

    let plan sql =
      compile sql |> Result.map_error ~f:Sql.error_to_string |> Result.ok_or_failwith
    ;;

    let fields sql = Statement_plan.fields (plan sql)

    let%test_unit "lateral correlation" =
      ignore
        (plan
           {sql|SELECT p.id, q.label FROM join_people p CROSS JOIN LATERAL (SELECT l.label FROM join_links l WHERE l.person_id=p.id) q|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "left lateral" =
      ignore
        (plan
           {sql|SELECT p.id, q.label FROM join_people p LEFT JOIN LATERAL (SELECT l.label FROM join_links l WHERE l.person_id=p.id LIMIT $limit) q ON true|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "comma lateral" =
      ignore
        (plan {sql|SELECT q.id FROM join_people p, LATERAL (SELECT p.id) q|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "nested lateral visibility" =
      ignore
        (plan
           {sql|SELECT q.id FROM join_people p, join_links l JOIN LATERAL (SELECT p.id+l.id AS id) q ON true|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "uncorrelated right lateral" =
      ignore
        (plan
           {sql|SELECT p.id FROM join_people p RIGHT JOIN LATERAL (SELECT 1) q ON true|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "update from" =
      ignore
        (plan
           {sql|UPDATE join_people p SET name=l.label FROM join_links l WHERE p.id=l.person_id RETURNING p.id,l.label|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "delete using" =
      ignore
        (plan
           {sql|DELETE FROM join_people p USING join_links l WHERE p.id=l.person_id RETURNING p.id,l.label|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "update joined sources" =
      ignore
        (plan
           {sql|UPDATE join_people p SET name=x.name FROM join_links l JOIN join_people x ON x.id=l.person_id WHERE p.id=l.person_id|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "delete using CTE" =
      ignore
        (plan
           {sql|WITH ids AS (SELECT id FROM join_links) DELETE FROM join_people p USING ids WHERE p.id=ids.id RETURNING p.id|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "ranking windows" =
      ignore
        (plan
           {sql|SELECT row_number() OVER(),rank() OVER(ORDER BY name),dense_rank() OVER(ORDER BY id),percent_rank() OVER(ORDER BY id),cume_dist() OVER(ORDER BY id),ntile($buckets) OVER(ORDER BY id) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "window values" =
      ignore
        (plan
           {sql|SELECT lag(id,$distance,$fallback) OVER(ORDER BY id),lead(name) OVER(ORDER BY id),first_value(name) OVER(),last_value(name) OVER(),nth_value(name,2) OVER() FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "named windows" =
      ignore
        (plan
           {sql|SELECT sum(id) OVER more, count(*) OVER(base ORDER BY id) FROM join_people WINDOW base AS (PARTITION BY name), more AS (base ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "rows frame parameters" =
      ignore
        (plan
           {sql|SELECT sum(id) OVER(ORDER BY id ROWS BETWEEN $before PRECEDING AND $after FOLLOWING EXCLUDE CURRENT ROW) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "groups frame" =
      ignore
        (plan
           {sql|SELECT count(*) OVER(ORDER BY id GROUPS BETWEEN 1 PRECEDING AND 2 FOLLOWING EXCLUDE GROUP) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "numeric range" =
      ignore
        (plan
           {sql|SELECT count(*) OVER(ORDER BY id RANGE $distance PRECEDING EXCLUDE TIES) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "temporal range" =
      ignore
        (plan
           {sql|SELECT count(*) OVER(ORDER BY t RANGE $duration PRECEDING) FROM typmod_values|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "default range" =
      ignore
        (plan
           {sql|SELECT count(*) OVER(RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING EXCLUDE NO OTHERS) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "window grouped aggregates" =
      ignore
        (plan
           {sql|SELECT name, sum(count(*)) OVER(ORDER BY name) FROM join_people GROUP BY name|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "window filter" =
      ignore
        (plan
           {sql|SELECT sum(id) FILTER(WHERE active) OVER(ORDER BY id) FROM join_links|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "window ordering alias" =
      ignore
        (plan
           {sql|SELECT row_number() OVER(ORDER BY id) AS n FROM join_people ORDER BY n|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "text functions" =
      ignore
        (plan
           {sql|SELECT lower(name),upper(name),length(name),char_length(name),character_length(name),octet_length(name),replace(name,$old,$replacement),concat(name,id) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "trim syntax" =
      ignore
        (plan
           {sql|SELECT trim(name),trim(both from name),trim(leading 'x' from name),trim(trailing from name),ltrim(name,'x'),rtrim(name),btrim(name) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "substring syntax" =
      ignore
        (plan
           {sql|SELECT substring(name FROM 2 FOR $count),substring(name FOR 3),substr(name,1),substring(name,$start::integer,2) FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "numeric functions" =
      ignore
        (plan
           {sql|SELECT abs(join_people.id),abs($value),round(join_people.id),round($amount,2),round(n) FROM join_people CROSS JOIN typmod_values|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "JSON extraction" =
      ignore
        (plan
           {sql|SELECT document->$key,document->0,binary_document->>$key,document#>$path,binary_document#>>'{a,b}' FROM people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "distinct from" =
      ignore
        (plan
           {sql|SELECT note IS DISTINCT FROM $?note, id IS NOT DISTINCT FROM $id FROM join_people|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "same varchar modifier" =
      ignore
        (plan {sql|SELECT v::varchar(10),c::character(3) FROM typmod_values|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "changed varchar modifier" =
      ignore
        (plan
           {sql|SELECT v::varchar,v::varchar(20),c::char,c::bpchar FROM typmod_values|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "same numeric modifier" =
      ignore (plan {sql|SELECT n::numeric(8,2) FROM typmod_values|sql} : Statement_plan.t)
    ;;

    let%test_unit "changed numeric modifier" =
      ignore
        (plan
           {sql|SELECT n::numeric,n::numeric(8,1),n::numeric(10,-2) FROM typmod_values|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "same temporal modifier" =
      ignore
        (plan
           {sql|SELECT t::timestamp(3),z::timestamp(3) with time zone,tm::time(3),i::interval day to second(3) FROM typmod_values|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "changed temporal modifier" =
      ignore
        (plan
           {sql|SELECT t::timestamp,t::timestamp(6),tm::time(2),i::interval(3),i::interval FROM typmod_values|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "typmod derived column" =
      ignore
        (plan {sql|SELECT q.v::varchar(10) FROM (SELECT v FROM typmod_values) q|sql}
         : Statement_plan.t)
    ;;

    let%test_unit "cast group expression" =
      ignore
        (plan {sql|SELECT v::varchar(2) FROM typmod_values GROUP BY v::varchar(2)|sql}
         : Statement_plan.t)
    ;;

    let%test "non lateral forward reference" =
      Result.is_error
        (compile {sql|SELECT q.id FROM LATERAL (SELECT p.id) q,join_people p|sql})
    ;;

    let%test "right lateral correlation" =
      Result.is_error
        (compile
           {sql|SELECT q.id FROM join_people p RIGHT JOIN LATERAL (SELECT p.id) q ON true|sql})
    ;;

    let%test "full lateral correlation" =
      Result.is_error
        (compile
           {sql|SELECT q.id FROM join_people p FULL JOIN LATERAL (SELECT p.id) q ON true|sql})
    ;;

    let%test "table functions deferred" =
      Result.is_error (compile {sql|SELECT * FROM LATERAL generate_series(1,3) x|sql})
    ;;

    let%test "update target invisible in FROM" =
      Result.is_error
        (compile
           {sql|UPDATE join_people p SET name=q.name FROM LATERAL (SELECT p.name) q|sql})
    ;;

    let%test "update ambiguity" =
      Result.is_error
        (compile
           {sql|UPDATE join_people p SET name=l.label FROM join_links l WHERE id=1|sql})
    ;;

    let%test "update unknown target" =
      Result.is_error
        (compile {sql|UPDATE join_people p SET missing=l.label FROM join_links l|sql})
    ;;

    let%test "delete unknown USING column" =
      Result.is_error
        (compile
           {sql|DELETE FROM join_people p USING join_links l WHERE l.missing=p.id|sql})
    ;;

    let%test "window WHERE" =
      Result.is_error
        (compile {sql|SELECT id FROM join_people WHERE row_number() OVER()>1|sql})
    ;;

    let%test "window HAVING" =
      Result.is_error
        (compile {sql|SELECT count(*) FROM join_people HAVING row_number() OVER()>1|sql})
    ;;

    let%test "window GROUP BY" =
      Result.is_error
        (compile {sql|SELECT id FROM join_people GROUP BY row_number() OVER()|sql})
    ;;

    let%test "window GROUP BY alias" =
      Result.is_error
        (compile {sql|SELECT row_number() OVER() AS n FROM join_people GROUP BY n|sql})
    ;;

    let%test "window UPDATE" =
      Result.is_error (compile {sql|UPDATE join_people SET id=row_number() OVER()|sql})
    ;;

    let%test "window RETURNING" =
      Result.is_error
        (compile {sql|DELETE FROM join_people RETURNING row_number() OVER()|sql})
    ;;

    let%test "window aggregate argument" =
      Result.is_error (compile {sql|SELECT sum(row_number() OVER()) FROM join_people|sql})
    ;;

    let%test "nested window" =
      Result.is_error
        (compile {sql|SELECT lag(row_number() OVER()) OVER() FROM join_people|sql})
    ;;

    let%test "window inside specification" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(ORDER BY row_number() OVER()) FROM join_people|sql})
    ;;

    let%test "ungrouped window input" =
      Result.is_error
        (compile {sql|SELECT lag(id) OVER() FROM join_people GROUP BY name|sql})
    ;;

    let%test "ungrouped window specification" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(ORDER BY id) FROM join_people GROUP BY name|sql})
    ;;

    let%test "unknown window" =
      Result.is_error (compile {sql|SELECT count(*) OVER missing FROM join_people|sql})
    ;;

    let%test "forward window" =
      Result.is_error
        (compile {sql|SELECT count(*) OVER a FROM join_people WINDOW a AS(b),b AS()|sql})
    ;;

    let%test "duplicate windows" =
      Result.is_error (compile {sql|SELECT id FROM join_people WINDOW a AS(),a AS()|sql})
    ;;

    let%test "override partition" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(a PARTITION BY name) FROM join_people WINDOW a AS()|sql})
    ;;

    let%test "override ordering" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(a ORDER BY name) FROM join_people WINDOW a AS(ORDER BY id)|sql})
    ;;

    let%test "copy framed window" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(a) FROM join_people WINDOW a AS(ROWS 1 PRECEDING)|sql})
    ;;

    let%test "bad frame order" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(ROWS BETWEEN CURRENT ROW AND 1 PRECEDING) FROM join_people|sql})
    ;;

    let%test "groups without ordering" =
      Result.is_error
        (compile {sql|SELECT count(*) OVER(GROUPS 1 PRECEDING) FROM join_people|sql})
    ;;

    let%test "range many ordering fields" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(ORDER BY id,name RANGE 1 PRECEDING) FROM join_people|sql})
    ;;

    let%test "range unsupported type" =
      Result.is_error
        (compile
           {sql|SELECT count(*) OVER(ORDER BY name RANGE 1 PRECEDING) FROM join_people|sql})
    ;;

    let%test "frame column" =
      Result.is_error
        (compile {sql|SELECT count(*) OVER(ROWS id PRECEDING) FROM join_people|sql})
    ;;

    let%test "distinct window aggregate" =
      Result.is_error
        (compile {sql|SELECT count(DISTINCT id) OVER() FROM join_people|sql})
    ;;

    let%test "window aggregate order" =
      Result.is_error
        (compile {sql|SELECT sum(id ORDER BY id) OVER() FROM join_people|sql})
    ;;

    let%test "nonwindow OVER" =
      Result.is_error (compile {sql|SELECT lower(name) OVER() FROM join_people|sql})
    ;;

    let%test "unknown ordinary window call" =
      Result.is_error (compile {sql|SELECT row_number() FROM join_people|sql})
    ;;

    let%test "wrong builtin overload" =
      Result.is_error (compile {sql|SELECT lower(id) FROM join_people|sql})
    ;;

    let%test "unknown concat bind" =
      Result.is_error (compile {sql|SELECT concat($unknown) FROM join_people|sql})
    ;;

    let%test "regex substring deferred" =
      Result.is_error (compile {sql|SELECT substring(name,$pattern) FROM join_people|sql})
    ;;

    let%test "wrong JSON input" =
      Result.is_error (compile {sql|SELECT name->'key' FROM join_people|sql})
    ;;

    let%test "wrong JSON key" =
      Result.is_error (compile {sql|SELECT document->true FROM people|sql})
    ;;

    let%test "missing typmod metadata" =
      Result.is_error (compile {sql|SELECT note::varchar FROM people|sql})
    ;;

    let%test "invalid type modifier" =
      Result.is_error (compile {sql|SELECT id::integer(3) FROM join_people|sql})
    ;;

    let%test "different cast grouping" =
      Result.is_error
        (compile {sql|SELECT v::varchar(2) FROM typmod_values GROUP BY v::varchar(3)|sql})
    ;;

    let%test "polymorphic window argument needs a type" =
      Result.is_error (compile "SELECT lag($unknown) OVER()")
    ;;

    let%test_unit "constant window keys" =
      ignore
        (plan "SELECT count(*) OVER(PARTITION BY 'one' ORDER BY $key) FROM join_people"
         : Statement_plan.t)
    ;;

    let%test "unused window aggregate still requires grouping" =
      Result.is_error
        (compile "SELECT name FROM join_people WINDOW w AS (ORDER BY sum(id))")
    ;;

    let%test_unit "computed typmods survive derived columns" =
      ignore
        (plan
           "SELECT q.v::varchar(2) FROM (SELECT v::varchar(2) AS v FROM typmod_values) q"
         : Statement_plan.t)
    ;;

    let%test_unit "typmod CTE preserves direct column origin" =
      ignore
        (plan
           "WITH source AS(SELECT v FROM typmod_values) SELECT v::varchar(10) FROM source"
         : Statement_plan.t)
    ;;

    let%test "temporal modifier overflow" =
      Result.is_error (compile "SELECT t::timestamp(2147483648) FROM typmod_values")
    ;;

    let%test "quoted substring uses ordinary function syntax" =
      Result.is_error (compile {|SELECT "substring"(name FROM 1) FROM join_people|})
    ;;

    let%test "qualified substring uses ordinary function syntax" =
      Result.is_error
        (compile "SELECT pg_catalog.substring(name FROM 1) FROM join_people")
    ;;

    let%test "equal typmods retain column origin" =
      let result =
        fields
          "SELECT v::varchar(10),c::char(3),n::numeric(8,2),t::timestamp(3),i::interval day to second(3) FROM typmod_values"
      in
      List.for_all result ~f:(fun field -> not field.Statement_plan.nullable)
    ;;

    let%test "changed typmods discard column origin" =
      let result =
        fields
          "SELECT v::varchar,c::char(2),n::numeric(9,2),t::timestamp,i::interval FROM typmod_values"
      in
      List.for_all result ~f:(fun field -> field.Statement_plan.nullable)
    ;;

    let%test "new expressions retain upstream optional results" =
      let result =
        fields
          "SELECT lower(name),row_number() OVER(),id IS DISTINCT FROM 0 FROM join_people"
      in
      List.for_all result ~f:(fun field -> field.Statement_plan.nullable)
    ;;

    let%test "window argument and frame parameter codecs" =
      let result =
        plan
          "SELECT lag(id,$distance,$fallback) OVER(ORDER BY id ROWS $frame PRECEDING) FROM join_people"
      in
      List.equal
        String.equal
        (List.map result.parameters ~f:(fun p -> Codec.to_string p.Statement_plan.codec))
        [ "int32"; "int32"; "int64" ]
    ;;

    let%test "round uses float8 for integer input" =
      List.equal
        String.equal
        (List.map (fields "SELECT round(join_people.id) FROM join_people") ~f:(fun f ->
           Codec.to_string f.Statement_plan.codec))
        [ "float" ]
    ;;

    let%test "literals do not produce bind slots" =
      let result =
        plan
          {sql|SELECT E'\n$fake', $tag$${fake} -- $id$tag$, $$ $@list $$, $real::integer|sql}
      in
      Int.equal (List.length result.parameters) 1
    ;;
  end)
;;
