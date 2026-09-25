open! Base
open Typed_sql
open Infix
module T = Caqti.Template
module Adapter = Typed_sql_caqti_lwt

let ( let* ) = Lwt.bind
let ( >>= ) = Lwt.bind

let direct sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit)
    (fun _ -> T.Query.parse sql)
;;

let or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

let adapter_or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Adapter.error_to_string error)
;;

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "postgres_items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
end

module Department = struct
  type row

  let table : row Table.t = Table.v_exn "postgres_departments"
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let person_id row = Expr.column row person_id_column
  let name row = Expr.column row name_column
end

module Selected_item = struct
  type row

  let table : row Table.t = Table.v_exn "selected_postgres_items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
  let projection row = Projection.pair (id row) (name row)
end

module Number = struct
  type row

  let table : row Table.t = Table.v_exn "recursive_numbers"
  let value_column = Column.v_exn table "value" Db_type.int64
  let value row = Expr.column row value_column
end

module Constraint_item = struct
  type row

  let table : row Table.t = Table.v_exn "postgres_constraints"
  let id_column = Column.v_exn table "id" Db_type.int64
  let parent_column = Column.v_exn table "parent_id" Db_type.int64
  let value_column = Column.v_exn table "value" Db_type.int64
  let note_column = Column.nullable_v_exn table "note" Db_type.text
end

module Sqlstate_item = struct
  type row

  let table : row Table.t = Table.v_exn "postgres_sqlstate_cases"
  let code_column = Column.v_exn table "code" Db_type.text
end

module Deferred_child = struct
  type row

  let table : row Table.t = Table.v_exn "postgres_deferred_child"
  let id_column = Column.v_exn table "id" Db_type.int64
end

module Numeric_item = struct
  type row

  let table : row Table.t = Table.v_exn "postgres_numeric_items"
  let amount_column = Column.v_exn table "amount" Db_type.numeric
  let amount row = Expr.column row amount_column
end

let decimal_exn value =
  match Decimal.of_string value with
  | Some value -> value
  | None -> failwith "invalid test decimal"
;;

module Codec_item = struct
  type row

  let table : row Table.t = Table.v_exn "postgres_codec_items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let boolean_column = Column.v_exn table "boolean_value" Db_type.bool
  let integer_column = Column.v_exn table "integer_value" Db_type.int
  let float_column = Column.v_exn table "float_value" Db_type.float
  let text_column = Column.v_exn table "text_value" Db_type.text
  let bytes_column = Column.v_exn table "bytes_value" Db_type.bytes
  let date_column = Column.v_exn table "date_value" Db_type.date
  let timestamp_column = Column.v_exn table "timestamp_value" Db_type.timestamp
  let uuid_column = Column.v_exn table "uuid_value" Db_type.uuid
  let nullable_column = Column.nullable_v_exn table "nullable_value" Db_type.text

  let projection row =
    Projection.both
      (Projection.both
         (Projection.both
            (Projection.expr (Expr.column row boolean_column))
            (Projection.expr (Expr.column row integer_column)))
         (Projection.both
            (Projection.expr (Expr.column row float_column))
            (Projection.expr (Expr.column row text_column))))
      (Projection.both
         (Projection.both
            (Projection.expr (Expr.column row bytes_column))
            (Projection.expr (Expr.column row date_column)))
         (Projection.both
            (Projection.expr (Expr.column row timestamp_column))
            (Projection.both
               (Projection.expr (Expr.column row uuid_column))
               (Projection.expr (Expr.column row nullable_column)))))
  ;;
end

let date_exn value =
  match Date.of_string value with
  | Some value -> value
  | None -> failwith "invalid test date"
;;

let timestamp_exn value =
  match Ptime.of_rfc3339 value with
  | Ok (value, _, _) -> value
  | Error _ -> failwith "invalid test timestamp"
;;

let uuid_exn value =
  match Uuid.of_string value with
  | Some value -> value
  | None -> failwith "invalid test UUID"
;;

let equal_pair (a, b) (c, d) = Int64.(a = c) && String.equal b d

let fetch conn query =
  let statement = Statement.Portable.query_many_exn (fun _ -> query) in
  Adapter.run ~conn statement () >>= adapter_or_fail
;;

let execute conn command =
  let statement = Statement.Portable.command_exn (fun _ -> command) in
  Adapter.run ~conn statement () >>= adapter_or_fail
;;

let fetch_postgresql conn query =
  let statement =
    Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun _ -> query)
  in
  Adapter.run ~conn statement () >>= adapter_or_fail
;;

let assert_rows ~name ~equal expected actual =
  if not (List.equal equal expected actual) then
    failwith (name ^ ": unexpected query result")
;;

let check_golden conn ~name ~equal ~expected query =
  let* actual = fetch conn query in
  assert_rows ~name ~equal expected actual;
  Lwt.return_unit
;;

let run_goldens ~postgresql conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let* () =
    if postgresql then
      Lwt.return_unit
    else
      Connection.exec (direct "ATTACH DATABASE ':memory:' AS public") () |> or_fail
  in
  let people_ddl =
    if postgresql then
      "CREATE TABLE \"public\".\"people\" (id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, name TEXT DEFAULT 'unknown', nickname TEXT)"
    else
      "CREATE TABLE \"public\".\"people\" (id INTEGER PRIMARY KEY, name TEXT DEFAULT 'unknown', nickname TEXT)"
  in
  let statements =
    [ people_ddl
    ; "CREATE TABLE \"public\".\"departments\" (person_id BIGINT, name TEXT NOT NULL)"
    ; "CREATE TABLE \"public\".\"sales\" (person_id BIGINT, quantity INTEGER, unit_price DOUBLE PRECISION, amount NUMERIC, region TEXT)"
    ; "CREATE TABLE \"public\".\"events\" (occurred_at TIMESTAMP WITH TIME ZONE)"
    ; "CREATE TABLE \"public\".\"calendar_days\" (calendar_date DATE)"
    ; "CREATE TABLE \"public\".\"resources\" (external_id UUID)"
    ; "CREATE TABLE \"public\".\"blobs\" (value BYTEA)"
    ; "CREATE TABLE aggregate_items (int_value INTEGER, nullable_int_value INTEGER, int64_value BIGINT, nullable_int64_value BIGINT, float_value DOUBLE PRECISION, nullable_float_value DOUBLE PRECISION, text_value TEXT, numeric_value NUMERIC, nullable_numeric_value NUMERIC)"
    ; "CREATE TABLE items (id INTEGER, name TEXT)"
    ; "CREATE TABLE excluded (id BIGINT NOT NULL, name TEXT NOT NULL, nickname TEXT, UNIQUE (id, name))"
    ; "INSERT INTO \"public\".\"people\" VALUES (1, 'Ada', NULL), (2, 'Grace', 'Amazing'), (3, 'Linus', 'Lin'), (4, 'Edsger', NULL)"
    ; "INSERT INTO \"public\".\"departments\" VALUES (1, 'Math'), (3, 'Computing')"
    ; "INSERT INTO \"public\".\"sales\" VALUES (1, 2, 3.0, 6.0, 'north'), (2, 1, 4.0, 4.0, 'south')"
    ; "INSERT INTO \"public\".\"events\" VALUES ('2020-01-01T00:00:00Z')"
    ; "INSERT INTO \"public\".\"calendar_days\" VALUES ('2026-09-12')"
    ; "INSERT INTO \"public\".\"resources\" VALUES ('550e8400-e29b-41d4-a716-446655440000')"
    ; "INSERT INTO aggregate_items VALUES (1, NULL, 2, NULL, 1.5, NULL, 'a', 2.5, NULL), (2, 3, 4, 5, 2.5, 3.5, 'b', 4.5, 6.5)"
    ; "INSERT INTO items VALUES (1, 'one'), (2, NULL), (3, 'three'), (4, NULL)"
    ]
  in
  let* () =
    Lwt_list.iter_s
      (fun statement -> Connection.exec (direct statement) () |> or_fail)
      statements
  in
  let* () =
    if postgresql then
      Lwt.return_unit
    else
      let* () =
        Connection.exec (direct "CREATE TABLE people (id BIGINT, name TEXT)") ()
        |> or_fail
      in
      Connection.exec
        (direct
           "INSERT INTO people VALUES (1, 'Ada'), (2, 'Grace'), (3, 'Linus'), (4, 'Edsger')")
        ()
      |> or_fail
  in
  let module Q = Typed_sql_expect_tests.Query_test in
  let module R = Typed_sql_expect_tests.Relational_query_test in
  let module A = Typed_sql_expect_tests.Aggregate_test in
  let module P = Typed_sql_expect_tests.Public_api_test in
  let module U = Typed_sql_expect_tests.Upsert_test in
  let module D = Typed_sql_expect_tests.Dynamic_statement_test in
  let check_person_ids name expected query =
    let* rows = fetch conn query in
    let ids = List.map rows ~f:(fun (row : Q.Person.t) -> row.id) in
    assert_rows ~name ~equal:Int64.equal expected ids;
    Lwt.return_unit
  in
  let* () = check_person_ids "empty IN golden" [] Q.empty_in_query in
  let* () =
    check_person_ids "empty NOT IN golden" [ 1L; 2L; 3L; 4L ] Q.empty_not_in_query
  in
  let infix_comparisons =
    Query.(
      from Q.Person.table
      |> where (fun person ->
        Q.Person.id person
        <$ 1L
        &&. (Q.Person.id person <=$ 2L)
        &&. (Q.Person.id person >$ 3L)
        &&. (Q.Person.id person >=$ 4L)
        &&. (Q.Person.id person <>$ 5L)
        &&. (Q.Person.name person =~$ "A%"))
      |> select Q.Person.projection)
  in
  let* () = check_person_ids "infix comparison golden" [] infix_comparisons in
  let empty_case =
    Query.(
      from Q.Person.table
      |> select (fun person ->
        Projection.expr (Expr.case [] ~else_:(Q.Person.name person))))
  in
  let* () =
    check_golden
      conn
      ~name:"empty CASE golden"
      ~equal:String.equal
      ~expected:[ "Ada"; "Grace"; "Linus"; "Edsger" ]
      empty_case
  in
  let negated_subqueries =
    Query.(
      from Q.Person.table
      |> where (fun person ->
        Query.(from Q.Department.table |> not_exists)
        &&. not_in_subquery
              (Q.Person.id person)
              Query.(from Q.Department.table |> select_scalar Q.Department.person_id))
      |> select Q.Person.projection)
  in
  let* () = check_person_ids "negated subqueries golden" [] negated_subqueries in
  let* () =
    Connection.exec (direct "CREATE TABLE \"select\" (\"quoted\"\"name\" TEXT)") ()
    |> or_fail
  in
  let* () =
    Connection.exec (direct "INSERT INTO \"select\" VALUES ('quoted')") () |> or_fail
  in
  let quoted_table : unit Table.t = Table.v_exn "select" in
  let quoted_column = Column.v_exn quoted_table "quoted\"name" Db_type.text in
  let quoted_query =
    Query.(
      from quoted_table
      |> select (fun reference -> Projection.expr (Expr.column reference quoted_column)))
  in
  let* () =
    check_golden
      conn
      ~name:"quoted identifiers golden"
      ~equal:String.equal
      ~expected:[ "quoted" ]
      quoted_query
  in
  let* () =
    if postgresql then (
      let* rows = fetch_postgresql conn Q.having_constant_query in
      assert_rows
        ~name:"HAVING establishes aggregate context golden"
        ~equal:Int.equal
        [ 1 ]
        rows;
      Lwt.return_unit)
    else
      Lwt.return_unit
  in
  let* () =
    Lwt_list.iter_s
      (fun (predicate, expected) ->
         let input = { D.Search_people.Input.predicate; maximum_rows = 10 } in
         let* rows =
           Adapter.run ~conn D.Search_people.statement input >>= adapter_or_fail
         in
         assert_rows ~name:"dynamic comparison golden" ~equal:Int64.equal expected rows;
         Lwt.return_unit)
      [ D.Predicate.At_least 3L, [ 3L; 4L ]; D.Predicate.At_most 2L, [ 1L; 2L ] ]
  in
  let* aggregate = fetch conn A.portable_aggregate in
  (match aggregate with
   | [ (amount, (floating, (smallest, largest))) ] ->
     if
       not
         (Option.equal Int64.equal amount (Some 3L)
          && Option.equal Float.equal floating (Some 4.)
          && Option.equal String.equal smallest (Some "a")
          && Option.equal String.equal largest (Some "b"))
     then
       failwith "portable scalar aggregate golden returned wrong values"
   | _ -> failwith "portable scalar aggregate golden returned wrong cardinality");
  let* () =
    if postgresql then (
      let* rows = fetch_postgresql conn Q.numeric_sales_query in
      (match rows with
       | [ (sum, maximum) ]
         when Option.equal Decimal.equal sum (Some (decimal_exn "10"))
              && Option.equal Decimal.equal maximum (Some (decimal_exn "6")) -> ()
       | _ -> failwith "PostgreSQL numeric sales golden returned wrong values");
      let* rows = fetch_postgresql conn A.numeric_aggregate in
      (match rows with
       | [ ( sum_int64
           , ( sum_numeric
             , ( min_numeric
               , ( max_numeric
                 , ( sum_nullable_int64
                   , (sum_nullable_numeric, (min_nullable_numeric, max_nullable_numeric))
                   ) ) ) ) )
         ] ->
         let equal expected actual =
           Option.equal Decimal.equal actual (Some (decimal_exn expected))
         in
         if
           not
             (equal "6" sum_int64
              && equal "7" sum_numeric
              && equal "2.5" min_numeric
              && equal "4.5" max_numeric
              && equal "5" sum_nullable_int64
              && equal "6.5" sum_nullable_numeric
              && equal "6.5" min_nullable_numeric
              && equal "6.5" max_nullable_numeric)
         then
           failwith "PostgreSQL numeric aggregate golden lost exactness"
       | _ -> failwith "PostgreSQL numeric aggregate golden returned wrong cardinality");
      Lwt.return_unit)
    else
      Lwt.return_unit
  in
  let* selected_none =
    Adapter.run ~conn P.optional_filter_statement { P.name = None } >>= adapter_or_fail
  in
  assert_rows
    ~name:"optional parameter golden, absent"
    ~equal:Int.equal
    [ 1; 2; 3; 4 ]
    (List.sort selected_none ~compare:Int.compare);
  let* selected_one =
    Adapter.run ~conn P.optional_filter_statement { P.name = Some "one" }
    >>= adapter_or_fail
  in
  assert_rows
    ~name:"optional parameter golden, present"
    ~equal:Int.equal
    [ 1 ]
    selected_one;
  let null_and_sort = Query.(P.null_and_sort_query |> select P.projection) in
  let* () =
    check_golden
      conn
      ~name:"null checks and sort golden"
      ~equal:Int.equal
      ~expected:[ 2 ]
      null_and_sort
  in
  let* () =
    check_golden
      conn
      ~name:"filtered ordered SELECT golden"
      ~equal:equal_pair
      ~expected:[]
      Q.rendering_query
  in
  let* nested = fetch conn Q.nested_multiset_query in
  assert_rows
    ~name:"correlated multiset golden"
    ~equal:(fun (a, b) (c, d) -> String.equal a c && List.equal String.equal b d)
    [ "Ada", [ "Math" ]; "Edsger", []; "Grace", []; "Linus", [ "Computing" ] ]
    (List.sort nested ~compare:(fun (a, _) (b, _) -> String.compare a b));
  let* aggregate = fetch conn Q.aggregate_query in
  (match aggregate with
   | [ rows ] ->
     assert_rows
       ~name:"multiset aggregate golden"
       ~equal:equal_pair
       [ 1L, "Math"; 3L, "Computing" ]
       rows
   | _ -> failwith "multiset aggregate golden returned wrong cardinality");
  let* recursive = fetch conn Q.recursive_aggregate_query in
  (match recursive with
   | [ rows ] ->
     assert_rows
       ~name:"nested multiset aggregate golden"
       ~equal:(fun (a, b) (c, d) -> String.equal a c && List.equal String.equal b d)
       [ "Ada", [ "Math" ]; "Grace", []; "Linus", [ "Computing" ]; "Edsger", [] ]
       rows
   | _ -> failwith "nested multiset aggregate golden returned wrong cardinality");
  let* () =
    check_golden
      conn
      ~name:"source-free UNION ALL golden"
      ~equal:Int64.equal
      ~expected:[ 1L; 2L ]
      Q.source_free_union_query
  in
  let* () =
    check_golden
      conn
      ~name:"source-free CTE golden"
      ~equal:Int64.equal
      ~expected:[ 7L ]
      Q.source_free_cte_query
  in
  let* () =
    check_golden
      conn
      ~name:"portable predicates golden"
      ~equal:(fun (a, b) (c, d) -> String.equal a c && Int.(b = d))
      ~expected:[ "grace", 5 ]
      Q.portable_predicates_query
  in
  let* arithmetic = fetch conn Q.arithmetic_query in
  let expected_arithmetic =
    List.map [ 1L; 2L; 3L; 4L ] ~f:(fun id ->
      ( [ Int64.(id + 1L); Int64.(id - 2L); Int64.(id * 3L); Int64.(id / 4L) ]
      , [ 13; 10; 36; 3 ]
      , [ 13.; 10.; 36.; 3. ] ))
  in
  assert_rows
    ~name:"typed arithmetic golden"
    ~equal:(fun (a, b, c) (d, e, f) ->
      List.equal Int64.equal a d && List.equal Int.equal b e && List.equal Float.equal c f)
    expected_arithmetic
    (List.sort arithmetic ~compare:(fun (a, _, _) (b, _, _) ->
       Int64.compare (List.hd_exn a) (List.hd_exn b)));
  let* joined = fetch conn Q.inner_join_query in
  assert_rows
    ~name:"inner JOIN golden"
    ~equal:equal_pair
    [ 1L, "Math"; 3L, "Computing" ]
    (List.sort joined ~compare:(fun (a, _) (b, _) -> Int64.compare a b));
  let* left_joined = fetch conn Q.left_join_query in
  assert_rows
    ~name:"left JOIN golden"
    ~equal:(fun (a, b) (c, d) -> Int64.(a = c) && Option.equal String.equal b d)
    [ 1L, Some "Math"; 2L, None; 3L, Some "Computing"; 4L, None ]
    (List.sort left_joined ~compare:(fun (a, _) (b, _) -> Int64.compare a b));
  let* branch_rows = fetch conn (Query.union_all R.first_branch R.second_branch) in
  assert_rows
    ~name:"set branch ordering golden"
    ~equal:equal_pair
    [ 1L, "Ada"; 2L, "Grace"; 3L, "Linus" ]
    (List.sort branch_rows ~compare:(fun (a, _) (b, _) -> Int64.compare a b));
  let* () =
    check_golden
      conn
      ~name:"grouped aggregates golden"
      ~equal:(fun (a, b, c) (d, e, f) ->
        String.equal a d && Int64.(b = e) && Int64.(c = f))
      ~expected:[ "Ada", 1L, 0L; "Edsger", 1L, 0L; "Grace", 1L, 1L; "Linus", 1L, 1L ]
      Q.grouped_aggregate_query
  in
  let* distinct = fetch conn Q.distinct_query in
  assert_rows
    ~name:"DISTINCT golden"
    ~equal:String.equal
    [ "Ada"; "Edsger"; "Grace"; "Linus" ]
    (List.sort distinct ~compare:String.compare);
  let* () =
    check_golden
      conn
      ~name:"aggregate COALESCE golden"
      ~equal:Int64.equal
      ~expected:[ 4L ]
      Q.aggregate_coalesce_query
  in
  let* () =
    check_golden
      conn
      ~name:"COALESCE inside aggregate golden"
      ~equal:Int64.equal
      ~expected:[ 4L ]
      Q.coalesce_inside_aggregate_query
  in
  let* grouped_coalesce = fetch conn Q.grouped_coalesce_query in
  assert_rows
    ~name:"grouped COALESCE golden"
    ~equal:String.equal
    [ "Ada"; "Amazing"; "Edsger"; "Lin" ]
    (List.sort grouped_coalesce ~compare:String.compare);
  let* () =
    check_golden
      conn
      ~name:"lowered GROUP BY golden"
      ~equal:(fun (a, b) (c, d) -> String.equal a c && Int64.(b = d))
      ~expected:[ "ada", 1L; "edsger", 1L; "grace", 1L; "linus", 1L ]
      Q.lowered_group_query
  in
  let* arithmetic_group = fetch conn Q.arithmetic_group_query in
  assert_rows
    ~name:"arithmetic GROUP BY golden"
    ~equal:(fun (a, b) (c, d) -> Int64.(a = c) && Int64.(b = d))
    [ 2L, 1L; 4L, 1L; 6L, 1L; 8L, 1L ]
    (List.sort arithmetic_group ~compare:(fun (a, _) (b, _) -> Int64.compare a b));
  let* concatenated_group = fetch conn Q.concatenated_group_query in
  assert_rows
    ~name:"concatenated GROUP BY golden"
    ~equal:(fun (a, b) (c, d) -> String.equal a c && Int64.(b = d))
    [ "AdaAda", 1L; "EdsgerEdsger", 1L; "GraceGrace", 1L; "LinusLinus", 1L ]
    (List.sort concatenated_group ~compare:(fun (a, _) (b, _) -> String.compare a b));
  let* () =
    check_golden
      conn
      ~name:"sales aggregate golden"
      ~equal:(fun (a, b, c) (d, e, f) ->
        Int64.(a = d) && Option.equal Int64.equal b e && Option.equal String.equal c f)
      ~expected:[ 2L, Some 3L, Some "south" ]
      Q.sales_summary_query
  in
  let* grouped_sales = fetch conn Q.grouped_sales_query in
  assert_rows
    ~name:"grouped SUM and MIN golden"
    ~equal:(fun (a, b, c) (d, e, f) ->
      String.equal a d && Option.equal Float.equal b e && Option.equal Int.equal c f)
    [ "north", Some 3., Some 2; "south", Some 4., Some 1 ]
    (List.sort grouped_sales ~compare:(fun (a, _, _) (b, _, _) -> String.compare a b));
  let* correlated = fetch conn Q.correlated_sales_total_query in
  assert_rows
    ~name:"correlated scalar aggregate golden"
    ~equal:(fun (a, b) (c, d) ->
      String.equal a c && Option.equal (Option.equal Int64.equal) b d)
    [ "Ada", Some (Some 2L); "Edsger", None; "Grace", Some (Some 1L); "Linus", None ]
    (List.sort correlated ~compare:(fun (a, _) (b, _) -> String.compare a b));
  let* () =
    check_golden
      conn
      ~name:"scalar fallback golden"
      ~equal:String.equal
      ~expected:[ "Ada" ]
      Q.scalar_fallback_query
  in
  let* () =
    check_golden
      conn
      ~name:"calendar date golden"
      ~equal:Date.equal
      ~expected:[ Q.calendar_date ]
      Q.calendar_date_query
  in
  let* () =
    check_golden
      conn
      ~name:"UUID golden"
      ~equal:Uuid.equal
      ~expected:[ Q.external_uuid ]
      Q.uuid_query
  in
  let* () =
    check_golden
      conn
      ~name:"correlated EXISTS and IN golden"
      ~equal:(fun (a, b) (c, d) -> String.equal a c && Option.equal String.equal b d)
      ~expected:[ "Ada", Some "Math"; "Linus", Some "Computing" ]
      Q.correlated_subquery_query
  in
  let* () =
    check_golden
      conn
      ~name:"zero-limit scalar golden"
      ~equal:(Option.equal String.equal)
      ~expected:[ None; None; None; None ]
      Q.zero_limit_scalar_query
  in
  let* () =
    check_golden
      conn
      ~name:"aggregate scalar golden"
      ~equal:(Option.equal Int64.equal)
      ~expected:[ Some 2L; Some 2L; Some 2L; Some 2L ]
      Q.aggregate_scalar_query
  in
  let* () =
    check_golden
      conn
      ~name:"nullable scalar golden"
      ~equal:(Option.equal String.equal)
      ~expected:[ Some "Math"; Some "Math"; Some "Math"; Some "Math" ]
      Q.nullable_scalar_query
  in
  let* () =
    check_golden
      conn
      ~name:"CURRENT_TIMESTAMP predicate golden"
      ~equal:Ptime.equal
      ~expected:[ timestamp_exn "2020-01-01T00:00:00Z" ]
      Q.current_timestamp_query
  in
  let relation =
    Query.(from_derived R.active_people |> select R.Selected_person.projection)
  in
  let* () =
    check_golden
      conn
      ~name:"derived relation golden"
      ~equal:equal_pair
      ~expected:[ 1L, "Ada" ]
      relation
  in
  let inferred =
    Query.(
      from_relation R.inferred_active_people
      |> where (fun (id, _name) -> id >$ 10L)
      |> select (fun (id, name) -> Projection.pair id name))
  in
  let* () =
    check_golden
      conn
      ~name:"inferred relation golden"
      ~equal:equal_pair
      ~expected:[]
      inferred
  in
  let derived_filtered =
    Query.(
      from_derived R.active_people
      |> where (fun person -> R.Selected_person.id person >$ 10L)
      |> select R.Selected_person.projection)
  in
  let* () =
    check_golden
      conn
      ~name:"filtered derived relation golden"
      ~equal:equal_pair
      ~expected:[]
      derived_filtered
  in
  let materialized =
    Cte.with_result R.materialized_people ~f:(fun people ->
      Query.(
        from_cte people
        |> where (fun person -> R.Selected_person.id person >$ 10L)
        |> select R.Selected_person.projection))
  in
  let* () =
    check_golden
      conn
      ~name:"materialized CTE golden"
      ~equal:equal_pair
      ~expected:[]
      materialized
  in
  let recursive =
    Cte.with_result R.recursive_numbers ~f:(fun numbers ->
      Query.(
        from_cte numbers |> select (fun number -> Projection.expr (R.Number.value number))))
  in
  let* rows = fetch conn recursive in
  assert_rows
    ~name:"recursive UNION ALL golden"
    ~equal:Int64.equal
    [ 1L; 2L; 2L; 3L; 3L; 3L; 4L; 4L; 4L; 5L; 5L; 5L ]
    (List.sort rows ~compare:Int64.compare);
  let* inserted = fetch conn Q.insert_returning_query in
  assert_rows ~name:"INSERT RETURNING golden" ~equal:Int64.equal [ 42L ] inserted;
  let* _ = execute conn Q.update_command in
  let updated =
    Query.(
      from Q.Person.table
      |> where (fun person -> Q.Person.id person =$ 42L)
      |> select (fun person -> Projection.expr (Q.Person.name person)))
  in
  let* () =
    check_golden
      conn
      ~name:"UPDATE command golden"
      ~equal:String.equal
      ~expected:[ "Grace" ]
      updated
  in
  let* _ = execute conn Q.delete_command in
  let* remaining = fetch conn Q.distinct_query in
  assert_rows ~name:"DELETE command golden" ~equal:String.equal [] remaining;
  let* _ = execute conn Q.multi_row_insert in
  let* _ = execute conn Q.insert_do_nothing in
  let* _ = execute conn Q.targeted_do_nothing in
  let* names = fetch conn Q.distinct_query in
  assert_rows
    ~name:"multi-row INSERT and DO NOTHING goldens"
    ~equal:String.equal
    [ "Ada"; "Grace" ]
    (List.sort names ~compare:String.compare);
  let* _ = execute conn Q.delete_command in
  let* () =
    if postgresql then (
      let statement =
        Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
          Q.default_insert)
      in
      let* _ = Adapter.run ~conn statement () >>= adapter_or_fail in
      let* names = fetch conn Q.distinct_query in
      assert_rows ~name:"DEFAULT INSERT golden" ~equal:String.equal [ "Ada" ] names;
      Lwt.return_unit)
    else
      Lwt.return_unit
  in
  let* _ = execute conn Q.delete_command in
  let* () =
    Connection.exec
      (direct
         "INSERT INTO \"public\".\"people\" (id, name) VALUES (1, 'Ada'), (2, 'Grace'), (3, 'Linus')")
      ()
    |> or_fail
  in
  let* _ = execute conn Q.update_from_command in
  let names_after_join =
    Query.(
      from Q.Person.table
      |> order_by Q.Person.id `Asc
      |> select (fun person -> Projection.expr (Q.Person.name person)))
  in
  let* () =
    check_golden
      conn
      ~name:"UPDATE FROM golden"
      ~equal:String.equal
      ~expected:[ "Math"; "Grace"; "Computing" ]
      names_after_join
  in
  let* _ = execute conn Q.delete_command in
  let* () =
    Connection.exec
      (direct "INSERT INTO \"public\".\"people\" (id, name) VALUES (1, 'Ada')")
      ()
    |> or_fail
  in
  let* updated = fetch conn Q.do_update_insert in
  assert_rows
    ~name:"ON CONFLICT DO UPDATE golden"
    ~equal:equal_pair
    [ 2L, "AdaAda!" ]
    updated;
  let* () =
    if postgresql then (
      let default_update =
        Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
          Q.default_update_command)
      in
      let* _ = Adapter.run ~conn default_update () >>= adapter_or_fail in
      let* names = fetch conn names_after_join in
      assert_rows ~name:"UPDATE DEFAULT golden" ~equal:String.equal [ "unknown" ] names;
      let* _ = execute conn Q.delete_command in
      let inserted_cte =
        Cte.with_result R.inserted_people ~f:(fun people ->
          Query.(from_cte people |> select R.Selected_person.projection))
      in
      let inserted_cte =
        Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun _ ->
          inserted_cte)
      in
      let* inserted = Adapter.run ~conn inserted_cte () >>= adapter_or_fail in
      (match inserted with
       | [ (id, "Ada") ] when Int64.(id > 0L) -> ()
       | _ -> failwith "data-modifying CTE golden returned wrong rows");
      let command_cte =
        Cte.with_command R.command_effect ~f:(fun () ->
          Insert.(
            into Q.Person.table
            |> default Q.Person.id_column
            |> set Q.Person.name_column "Grace"
            |> command))
      in
      let command_cte =
        Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
          command_cte)
      in
      let* _ = Adapter.run ~conn command_cte () >>= adapter_or_fail in
      let* names = fetch conn names_after_join in
      assert_rows
        ~name:"data-modifying CTE command golden"
        ~equal:String.equal
        [ "unknown"; "Grace" ]
        names;
      Lwt.return_unit)
    else
      Lwt.return_unit
  in
  let* _ = execute conn Q.current_timestamp_insert in
  let* timestamps = fetch conn Q.current_timestamp_query in
  if not Int.(List.length timestamps = 2) then
    failwith "CURRENT_TIMESTAMP INSERT golden returned wrong row count";
  let* updated = fetch conn P.updated_returning in
  assert_rows ~name:"UPDATE RETURNING golden" ~equal:Int.equal [ 2; 2 ] updated;
  let* deleted = fetch conn P.deleted_returning in
  assert_rows
    ~name:"DELETE RETURNING golden"
    ~equal:Int.equal
    [ 2; 2; 3 ]
    (List.sort deleted ~compare:Int.compare);
  let* () =
    Connection.exec (direct "INSERT INTO excluded VALUES (1, 'Ada', 'initial')") ()
    |> or_fail
  in
  let* upserted = fetch conn U.conditional_upsert in
  assert_rows
    ~name:"conditional composite UPSERT golden"
    ~equal:(fun (left_name, left_nine) (right_name, right_nine) ->
      String.equal left_name right_name && Int.equal left_nine right_nine)
    [ "Grace", 9 ]
    upserted;
  let* _ = execute conn U.target_do_nothing in
  let* _ = execute conn U.lowered_conflict_command in
  let upsert_rows =
    Query.(
      from U.table
      |> order_by (fun row -> Expr.column row U.id) `Asc
      |> select (fun row ->
        Projection.pair (Expr.column row U.name) (Expr.column row U.nickname)))
  in
  let* () =
    check_golden
      conn
      ~name:"targeted DO NOTHING and lowered conflict predicate goldens"
      ~equal:(fun (left_name, left_nickname) (right_name, right_nickname) ->
        String.equal left_name right_name
        && Option.equal String.equal left_nickname right_nickname)
      ~expected:[ "Ada", Some "initial"; "Grace", None ]
      upsert_rows
  in
  let conditional_update =
    Update.(
      table Q.Person.table
      |> set_opt Q.Person.name_column None
      |> set_opt Q.Person.nickname_column (Some None)
      |> set_expr_opt Q.Person.id_column None
      |> set_expr_opt Q.Person.id_column (Some (Expr.constant Db_type.int64 2L))
      |> where (fun person -> Q.Person.id person =$ 1L)
      |> command)
  in
  let* () =
    Connection.exec (direct "DELETE FROM \"public\".\"people\" WHERE id = 2") ()
    |> or_fail
  in
  let* _ = execute conn conditional_update in
  Lwt.return_unit
;;

let run conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let* () =
    Connection.exec
      (direct "CREATE TABLE postgres_items (id BIGINT PRIMARY KEY, name TEXT NOT NULL)")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct "CREATE TABLE postgres_departments (person_id BIGINT, name TEXT NOT NULL)")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE postgres_codec_items (id BIGINT PRIMARY KEY, boolean_value BOOLEAN NOT NULL, integer_value INTEGER NOT NULL, float_value DOUBLE PRECISION NOT NULL, text_value TEXT NOT NULL, bytes_value BYTEA NOT NULL, date_value DATE NOT NULL, timestamp_value TIMESTAMP WITH TIME ZONE NOT NULL, uuid_value UUID NOT NULL, nullable_value TEXT)")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct "INSERT INTO postgres_items VALUES (1, 'Ada'), (2, 'Grace'), (3, 'Linus')")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct
         "INSERT INTO postgres_departments VALUES (1, 'Math'), (1, 'Logic'), (3, 'Computing')")
      ()
    |> or_fail
  in
  let insert =
    Statement.Portable.command_exn (fun _ ->
      Insert.(
        into Item.table
        |> set Item.id_column 4L
        |> set Item.name_column "Edsger"
        |> command))
  in
  let* _ = Adapter.run ~conn insert () >>= adapter_or_fail in
  let query =
    Statement.Portable.query_many_exn (fun _ ->
      Query.(
        from Item.table
        |> order_by Item.id `Asc
        |> select (fun row -> Projection.pair (Item.id row) (Item.name row))))
  in
  let* rows = Adapter.run ~conn query () >>= adapter_or_fail in
  assert_rows
    ~name:"basic query"
    ~equal:equal_pair
    [ 1L, "Ada"; 2L, "Grace"; 3L, "Linus"; 4L, "Edsger" ]
    rows;
  let date = date_exn "2024-02-29" in
  let timestamp = timestamp_exn "2024-02-29T12:34:56Z" in
  let uuid = uuid_exn "123e4567-e89b-12d3-a456-426614174000" in
  let bytes = Bytes.of_string "a\000b\\c" in
  let codec_insert =
    Statement.Portable.command_exn (fun _ ->
      Insert.(
        into Codec_item.table
        |> set Codec_item.id_column 1L
        |> set Codec_item.boolean_column true
        |> set Codec_item.integer_column 42
        |> set Codec_item.float_column 1.5
        |> set Codec_item.text_column "O'Reilly"
        |> set Codec_item.bytes_column bytes
        |> set Codec_item.date_column date
        |> set Codec_item.timestamp_column timestamp
        |> set Codec_item.uuid_column uuid
        |> set Codec_item.nullable_column None
        |> command))
  in
  let* _ = Adapter.run ~conn codec_insert () >>= adapter_or_fail in
  let codec_query = Query.(from Codec_item.table |> select Codec_item.projection) in
  let* codec_rows = fetch conn codec_query in
  (match codec_rows with
   | [ ( ((boolean, integer), (floating, text))
       , ((actual_bytes, actual_date), (actual_timestamp, (actual_uuid, nullable))) )
     ] ->
     if
       not
         (Bool.equal boolean true
          && Int.(integer = 42)
          && Float.(floating = 1.5)
          && String.equal text "O'Reilly"
          && Bytes.equal actual_bytes bytes
          && Date.equal actual_date date
          && Ptime.equal actual_timestamp timestamp
          && Uuid.equal actual_uuid uuid
          && Option.is_none nullable)
     then
       failwith "Caqti codec round-trip failed"
   | _ -> failwith "Caqti codec query returned unexpected row count");
  let multiset =
    Query.(
      from Item.table
      |> order_by Item.id `Asc
      |> select (fun item ->
        let departments =
          Query.(
            from Department.table
            |> where (fun department -> Department.person_id department =. Item.id item)
            |> order_by Department.name `Asc
            |> select (fun department -> Projection.expr (Department.name department)))
        in
        Projection.both (Projection.expr (Item.name item)) (Query.multiset departments)))
  in
  let* rows = fetch conn multiset in
  assert_rows
    ~name:"correlated multiset"
    ~equal:(fun (a, b) (c, d) -> String.equal a c && List.equal String.equal b d)
    [ "Ada", [ "Logic"; "Math" ]; "Grace", []; "Linus", [ "Computing" ]; "Edsger", [] ]
    rows;
  let selected =
    Derived_table.create
      ~table:Selected_item.table
      ~columns:Selected_item.projection
      Query.(
        from Item.table
        |> where (fun item -> Item.id item <=$ 2L)
        |> select (fun item -> Projection.pair (Item.id item) (Item.name item)))
  in
  let derived =
    Query.(
      from_derived selected
      |> order_by Selected_item.id `Asc
      |> select Selected_item.projection)
  in
  let* rows = fetch conn derived in
  assert_rows ~name:"derived query" ~equal:equal_pair [ 1L, "Ada"; 2L, "Grace" ] rows;
  let left =
    Query.(
      from Item.table
      |> where (fun item -> Item.id item <=$ 2L)
      |> select (fun item -> Projection.expr (Item.id item)))
  in
  let right =
    Query.(
      from Item.table
      |> where (fun item -> Item.id item >=$ 2L)
      |> select (fun item -> Projection.expr (Item.id item)))
  in
  let* rows = fetch conn (Query.intersect left right) in
  assert_rows ~name:"INTERSECT" ~equal:Int64.equal [ 2L ] rows;
  let* rows = fetch conn (Query.except left right) in
  assert_rows ~name:"EXCEPT" ~equal:Int64.equal [ 1L ] rows;
  let* rows = fetch conn (Query.union left right) in
  assert_rows
    ~name:"UNION"
    ~equal:Int64.equal
    [ 1L; 2L; 3L; 4L ]
    (List.sort rows ~compare:Int64.compare);
  let cte = Cte.select ~materialization:`Materialized selected in
  let cte_query =
    Cte.with_result cte ~f:(fun items ->
      Query.(
        from_cte items
        |> order_by Selected_item.id `Asc
        |> select Selected_item.projection))
  in
  let* rows = fetch conn cte_query in
  assert_rows ~name:"materialized CTE" ~equal:equal_pair [ 1L, "Ada"; 2L, "Grace" ] rows;
  let numbers_relation query =
    Derived_table.create
      ~table:Number.table
      ~columns:(fun row -> Projection.expr (Number.value row))
      query
  in
  let recursive_numbers =
    Cte.recursive
      ~union:`Union
      ~anchor:
        (numbers_relation
           Query.(
             from Item.table
             |> where (fun item -> Item.id item <=$ 3L)
             |> select (fun item -> Projection.expr (Item.id item))))
      ~step:(fun numbers ->
        numbers_relation
          Query.(
            from_cte numbers
            |> where (fun number -> Number.value number <$ 5L)
            |> select (fun number ->
              let open Expr.Int64.Infix in
              Projection.expr (Number.value number +. Expr.constant Db_type.int64 1L))))
  in
  let recursive_query =
    Cte.with_result recursive_numbers ~f:(fun numbers ->
      Query.(
        from_cte numbers
        |> order_by Number.value `Asc
        |> select (fun number -> Projection.expr (Number.value number))))
  in
  let* rows = fetch conn recursive_query in
  assert_rows ~name:"recursive CTE" ~equal:Int64.equal [ 1L; 2L; 3L; 4L; 5L ] rows;
  let multiset_aggregate =
    Query.(
      from Department.table
      |> select_exactly_one (fun department ->
        Projection.multiset_agg
          ~order_by:[ Aggregate_order.asc (Department.name department) ]
          (Projection.pair (Department.person_id department) (Department.name department))))
  in
  let* rows = fetch conn multiset_aggregate in
  (match rows with
   | [ rows ] ->
     assert_rows
       ~name:"JSON aggregate transport"
       ~equal:equal_pair
       [ 3L, "Computing"; 1L, "Logic"; 1L, "Math" ]
       rows
   | _ -> failwith "JSON aggregate cardinality failed");
  let count =
    Query.(from Item.table |> select (fun _ -> Projection.expr Expr.count_all))
  in
  let* rows = fetch conn count in
  assert_rows ~name:"aggregate cardinality" ~equal:Int64.equal [ 4L ] rows;
  let empty_count =
    Query.(
      from Item.table
      |> where (fun item -> Item.id item >$ 99L)
      |> select (fun _ -> Projection.expr Expr.count_all))
  in
  let* rows = fetch conn empty_count in
  assert_rows ~name:"empty aggregate cardinality" ~equal:Int64.equal [ 0L ] rows;
  let parameterized =
    Statement.Portable.query_many_exn (fun params ->
      let id = params.column ~name:"id" Item.id_column ~get:Fn.id in
      Query.(
        from Item.table
        |> where (fun item -> Item.id item >=. id &&. (Item.id item <=. id))
        |> select (fun item -> Projection.pair (Item.id item) (Item.name item))))
  in
  let* rows = Adapter.run ~conn parameterized 2L >>= adapter_or_fail in
  assert_rows ~name:"reused bind parameter" ~equal:equal_pair [ 2L, "Grace" ] rows;
  let* rows = Adapter.run ~conn parameterized 99L >>= adapter_or_fail in
  assert_rows ~name:"missing bind value" ~equal:equal_pair [] rows;
  let ignored =
    Statement.Portable.command_exn (fun _ ->
      Insert.(
        into Item.table
        |> set Item.id_column 1L
        |> set Item.name_column "ignored"
        |> on_conflict_do_nothing
        |> command))
  in
  let* _ = Adapter.run ~conn ignored () >>= adapter_or_fail in
  let* rows = Adapter.run ~conn query () >>= adapter_or_fail in
  assert_rows
    ~name:"conflict ignore"
    ~equal:equal_pair
    [ 1L, "Ada"; 2L, "Grace"; 3L, "Linus"; 4L, "Edsger" ]
    rows;
  Lwt.return_unit
;;

let postgres_only conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let rejecting_encode =
    Db_type.map
      ~name:"rejecting-encode"
      ~encode:(fun _ -> Error "rejected encode")
      ~decode:Result.return
      Db_type.text
  in
  let encode_query =
    Statement.For_dialect.query_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.select_one (Expr.constant rejecting_encode "value"))
  in
  let* encoded = Adapter.run ~conn encode_query () in
  (match encoded with
   | Error (Adapter.Codec "rejected encode") -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok _ -> failwith "Caqti accepted a rejected mapped encode");
  let rejecting_decode =
    Db_type.map
      ~name:"rejecting-decode"
      ~encode:Result.return
      ~decode:(fun _ -> Error "rejected decode")
      Db_type.text
  in
  let decoded_column = Column.v_exn Codec_item.table "text_value" rejecting_decode in
  let decode_query =
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(
        from Codec_item.table
        |> select (fun row -> Projection.expr (Expr.column row decoded_column))))
  in
  let* decoded = Adapter.run ~conn decode_query () in
  (match decoded with
   | Error (Adapter.Codec "rejected decode") -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok _ -> failwith "Caqti accepted a rejected mapped decode");
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE postgres_constraints (id BIGINT PRIMARY KEY, parent_id BIGINT REFERENCES postgres_items(id), value BIGINT CHECK (value > 0), note TEXT NOT NULL)")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct "CREATE TABLE postgres_numeric_items (amount NUMERIC NOT NULL)")
      ()
    |> or_fail
  in
  let insert_numeric amount =
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
      Insert.(into Numeric_item.table |> set Numeric_item.amount_column amount |> command))
  in
  let* _ =
    Adapter.run ~conn (insert_numeric (decimal_exn "9223372036854775807")) ()
    >>= adapter_or_fail
  in
  let* _ =
    Adapter.run ~conn (insert_numeric (decimal_exn "1.25")) () >>= adapter_or_fail
  in
  let numeric_sum =
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(
        from Numeric_item.table
        |> select (fun item ->
          Projection.expr (Postgresql.Numeric.sum_numeric (Numeric_item.amount item)))))
  in
  let* numeric_sum = Adapter.run ~conn numeric_sum () >>= adapter_or_fail in
  (match numeric_sum with
   | Some value when Decimal.equal value (decimal_exn "9223372036854775808.25") -> ()
   | _ -> failwith "Caqti numeric transport lost precision");
  let insert id parent value note =
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
      Insert.(
        into Constraint_item.table
        |> set Constraint_item.id_column id
        |> set Constraint_item.parent_column parent
        |> set Constraint_item.value_column value
        |> set Constraint_item.note_column note
        |> command))
  in
  let expect_constraint kind result =
    let equal_kind left right =
      match left, right with
      | Adapter.Unique, Adapter.Unique
      | Adapter.Foreign_key, Adapter.Foreign_key
      | Adapter.Not_null, Adapter.Not_null
      | Adapter.Check, Adapter.Check
      | Adapter.Restrict, Adapter.Restrict
      | Adapter.Exclusion, Adapter.Exclusion
      | Adapter.Other, Adapter.Other -> true
      | _ -> false
    in
    match result with
    | Error (Adapter.Constraint_violation { kind = actual; _ })
      when equal_kind kind actual -> ()
    | Error error -> failwith (Adapter.error_to_string error)
    | Ok _ -> failwith "expected PostgreSQL constraint violation"
  in
  let* first = Adapter.run ~conn (insert 1L 1L 1L (Some "ok")) () in
  let* _ = adapter_or_fail first in
  let* unique = Adapter.run ~conn (insert 1L 1L 1L (Some "duplicate")) () in
  expect_constraint Adapter.Unique unique;
  let* foreign_key = Adapter.run ~conn (insert 2L 999L 1L (Some "foreign")) () in
  expect_constraint Adapter.Foreign_key foreign_key;
  let* check = Adapter.run ~conn (insert 3L 1L (-1L) (Some "check")) () in
  expect_constraint Adapter.Check check;
  let* not_null = Adapter.run ~conn (insert 4L 1L 1L None) () in
  expect_constraint Adapter.Not_null not_null;
  let* () =
    Connection.exec (direct "CREATE TABLE postgres_sqlstate_cases (code TEXT)") ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE FUNCTION postgres_raise_sqlstate() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'forced SQLSTATE' USING ERRCODE = NEW.code; END $$")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TRIGGER raise_sqlstate BEFORE INSERT ON postgres_sqlstate_cases FOR EACH ROW EXECUTE FUNCTION postgres_raise_sqlstate()")
      ()
    |> or_fail
  in
  let trigger code =
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
      Insert.(into Sqlstate_item.table |> set Sqlstate_item.code_column code |> command))
  in
  let* () =
    Lwt_list.iter_s
      (fun (code, kind) ->
         let* result = Adapter.run ~conn (trigger code) () in
         expect_constraint kind result;
         Lwt.return_unit)
      [ "23505", Adapter.Unique
      ; "23503", Adapter.Foreign_key
      ; "23502", Adapter.Not_null
      ; "23514", Adapter.Check
      ; "23001", Adapter.Restrict
      ; "23P01", Adapter.Exclusion
      ; "23000", Adapter.Other
      ]
  in
  let* committed =
    Adapter.transaction ~conn ~f:(fun conn ->
      Adapter.run ~conn (insert 5L 1L 2L (Some "commit")) ())
  in
  let* _ = adapter_or_fail committed in
  let* rolled_back =
    Adapter.transaction ~conn ~f:(fun conn ->
      let* inserted = Adapter.run ~conn (insert 6L 1L 2L (Some "rollback")) () in
      match inserted with
      | Error error -> Lwt.return (Error error)
      | Ok _ -> Lwt.return (Error (Adapter.Schema "rollback marker")))
  in
  (match rolled_back with
   | Error (Adapter.Schema "rollback marker") -> ()
   | _ -> failwith "Caqti transaction rollback failed");
  let count id =
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(
        from Constraint_item.table
        |> where (fun row -> Expr.column row Constraint_item.id_column =$ id)
        |> select (fun _ -> Projection.expr Expr.count_all)))
  in
  let* committed_count = Adapter.run ~conn (count 5L) () >>= adapter_or_fail in
  let* rolled_back_count = Adapter.run ~conn (count 6L) () >>= adapter_or_fail in
  if not (Int64.(committed_count = 1L) && Int64.(rolled_back_count = 0L)) then
    failwith "Caqti transaction lifecycle failed";
  let* () =
    Connection.exec
      (direct "CREATE TABLE postgres_deferred_parent (id BIGINT PRIMARY KEY)")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE postgres_deferred_child (id BIGINT REFERENCES postgres_deferred_parent(id) DEFERRABLE INITIALLY DEFERRED)")
      ()
    |> or_fail
  in
  let deferred_insert =
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
      Insert.(into Deferred_child.table |> set Deferred_child.id_column 999L |> command))
  in
  let* commit_error =
    Adapter.transaction ~conn ~f:(fun conn -> Adapter.run ~conn deferred_insert ())
  in
  expect_constraint Adapter.Foreign_key commit_error;
  let* _ = Adapter.run ~conn (count 5L) () >>= adapter_or_fail in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE postgres_schema_parent (id BIGINT NOT NULL, code TEXT NOT NULL, PRIMARY KEY (id, code))")
      ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE postgres_schema_child (id BIGINT PRIMARY KEY, parent_id BIGINT NOT NULL, parent_code TEXT NOT NULL, nickname TEXT DEFAULT 'unknown', display_name TEXT GENERATED ALWAYS AS (nickname || '!') STORED, FOREIGN KEY (parent_id, parent_code) REFERENCES postgres_schema_parent (id, code), UNIQUE (parent_id, parent_code, nickname))")
      ()
    |> or_fail
  in
  let* schema = Adapter.Schema.introspect ~conn >>= adapter_or_fail in
  let constraint_table =
    List.find_exn (Schema_ir.tables schema) ~f:(fun table ->
      String.equal
        (Identifier.to_string (Schema_ir.table_name table))
        "postgres_constraints")
  in
  if
    not
      (Int.(List.length (Schema_ir.columns constraint_table) = 4)
       && Int.(List.length (Schema_ir.foreign_keys constraint_table) = 1))
  then
    failwith "PostgreSQL schema introspection lost columns or foreign key";
  let child =
    List.find_exn (Schema_ir.tables schema) ~f:(fun table ->
      String.equal
        (Identifier.to_string (Schema_ir.table_name table))
        "postgres_schema_child")
  in
  let find_column name =
    List.find_exn (Schema_ir.columns child) ~f:(fun column ->
      String.equal (Identifier.to_string (Schema_ir.column_name column)) name)
  in
  let names identifiers = List.map identifiers ~f:Identifier.to_string in
  let nickname = find_column "nickname" in
  let generated = find_column "display_name" in
  if
    not
      (Schema_ir.column_nullable nickname
       && Option.value_map
            (Schema_ir.column_default nickname)
            ~default:false
            ~f:(fun value -> String.is_substring value ~substring:"unknown")
       && Schema_ir.column_generated generated)
  then
    failwith "PostgreSQL schema introspection lost default or generated metadata";
  (match Schema_ir.foreign_keys child with
   | [ foreign_key ] ->
     if
       not
         (List.equal
            String.equal
            (names (Schema_ir.foreign_key_columns foreign_key))
            [ "parent_id"; "parent_code" ]
          && List.equal
               String.equal
               (names (Schema_ir.foreign_key_referenced_columns foreign_key))
               [ "id"; "code" ])
     then
       failwith "PostgreSQL composite foreign key was introspected incorrectly"
   | _ -> failwith "PostgreSQL composite foreign key was not introspected");
  (match Schema_ir.unique_constraints child with
   | [ constraint_ ] ->
     if
       not
         (List.equal
            String.equal
            (names (Schema_ir.unique_constraint_columns constraint_))
            [ "parent_id"; "parent_code"; "nickname" ])
     then
       failwith "PostgreSQL composite unique was introspected incorrectly"
   | _ -> failwith "PostgreSQL composite unique was not introspected");
  Lwt.return_unit
;;

let with_connection uri f =
  let* conn = Caqti_lwt_unix.connect (Uri.of_string uri) |> or_fail in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize (fun () -> f conn) (fun () -> Connection.disconnect ())
;;

let test_caqti_prepared conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let request =
    T.Request.create
      T.Request.Direct
      T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.int64)
      (fun _ -> T.Query.parse "SELECT count(*)::bigint FROM pg_prepared_statements")
  in
  let count () = Connection.find request () |> or_fail in
  let* existing = count () in
  if Int64.(existing <= 0L) then
    failwith "Caqti did not retain server-side prepared statements";
  let statement =
    Statement.Portable.query_one_exn (fun params ->
      Query.select_one (params.expr ~name:"value" Db_type.int64 ~get:Fn.id))
  in
  let* first = Adapter.run ~conn statement 11L >>= adapter_or_fail in
  let* after_first = count () in
  let* second = Adapter.run ~conn statement 12L >>= adapter_or_fail in
  let* after_second = count () in
  if
    not (Int64.(first = 11L) && Int64.(second = 12L) && Int64.(after_first = after_second))
  then
    failwith "Caqti did not reuse its connection-local prepared request";
  Lwt.return_unit
;;

let main () =
  let* () =
    with_connection "postgresql://" (fun conn ->
      let* () = run conn in
      let* () = test_caqti_prepared conn in
      let* () = postgres_only conn in
      run_goldens ~postgresql:true conn)
  in
  with_connection "sqlite3::memory:" (fun conn ->
    let* () = run conn in
    run_goldens ~postgresql:false conn)
;;

let () = Lwt_main.run (main ())
