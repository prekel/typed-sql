open! Base
open Typed_sql
open Infix
module T = Caqti.Template
module Adapter = Typed_sql_caqti_lwt

module Typed_sql_caqti_lwt = struct
  include Adapter

  let fetch ?observer ?name ~conn query =
    let statement = Statement.query_many ~dialect:Dialect.portable query in
    run ?observer ?name ~conn statement ()
  ;;

  let fetch_one ?observer ?name ~conn query =
    let statement = Statement.expect_one ~dialect:Dialect.portable query in
    run ?observer ?name ~conn statement ()
  ;;

  let fetch_opt ?observer ?name ~conn query =
    let statement = Statement.expect_optional ~dialect:Dialect.portable query in
    run ?observer ?name ~conn statement ()
  ;;

  let execute ?observer ?name ~conn command =
    let statement = Statement.command ~dialect:Dialect.portable command in
    run ?observer ?name ~conn statement ()
  ;;
end

let ( let* ) = Lwt.bind
let ( >>= ) = Lwt.bind

let caqti_or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

module Person = struct
  type row

  type role =
    [ `Admin
    | `Guest
    ]

  type t =
    { id : int64
    ; name : string
    ; role : role
    ; nickname : string option
    }

  let role_type =
    Db_type.map
      ~name:"role"
      ~encode:(function
        | `Admin -> Ok "admin"
        | `Guest -> Ok "guest")
      ~decode:(function
        | "admin" -> Ok `Admin
        | "guest" -> Ok `Guest
        | value -> Error ("unknown role: " ^ value))
      Db_type.text
  ;;

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let role_column = Column.v_exn table "role" role_type
  let nickname_column = Column.nullable_v_exn table "nickname" Db_type.text
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column
  let role reference = Expr.column reference role_column
  let nickname reference = Expr.column reference nickname_column

  let equal_role left right =
    match left, right with
    | `Admin, `Admin | `Guest, `Guest -> true
    | _ -> false
  ;;

  let equal left right =
    Int64.(left.id = right.id)
    && String.equal left.name right.name
    && equal_role left.role right.role
    && Option.equal String.equal left.nickname right.nickname
  ;;

  let projection reference =
    let identity ((id, name), (role, nickname)) = { id; name; role; nickname } in
    Projection.map
      ~f:identity
      (Projection.both
         (Projection.both
            (Projection.expr (id reference))
            (Projection.expr (name reference)))
         (Projection.both
            (Projection.expr (role reference))
            (Projection.expr (nickname reference))))
  ;;
end

type dialect_choice_input =
  { id : int64
  ; name : string
  }

let dialect_choice_statement =
  let postgresql =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let%map.Parameters id =
        params.column Person.id_column ~get:(fun input -> input.id)
      in
      params.query_many
        Query.(
          from Person.table
          |> where (fun person -> Person.id person =. id)
          |> select (fun person -> Projection.expr (Person.name person))))
  in
  let sqlite =
    Statement.with_parameters ~dialect:Dialect.sqlite (fun ~params ->
      let%map.Parameters name =
        params.column Person.name_column ~get:(fun input -> input.name)
      in
      params.query_many
        Query.(
          from Person.table
          |> where (fun person -> Person.name person =. name)
          |> select (fun person -> Projection.expr (Person.name person))))
  in
  Statement.choose_dialect ~postgresql ~sqlite
;;

module Selected_person = struct
  type row

  let table : row Table.t = Table.v_exn "selected_people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column
  let projection reference = Projection.pair (id reference) (name reference)
end

module Number = struct
  type row

  let table : row Table.t = Table.v_exn "numbers"
  let value_column = Column.v_exn table "value" Db_type.int64
  let value reference = Expr.column reference value_column
end

module Cross_left = struct
  type row

  let table : row Table.t = Table.v_exn "cross_join_left"
  let value_column = Column.v_exn table "value" Db_type.int
  let value reference = Expr.column reference value_column
end

module Cross_right = struct
  type row

  let table : row Table.t = Table.v_exn "cross_join_right"
  let value_column = Column.v_exn table "value" Db_type.int
  let value reference = Expr.column reference value_column
end

module Cross_empty = struct
  type row

  let table : row Table.t = Table.v_exn "cross_join_empty"
  let value_column = Column.v_exn table "value" Db_type.int
  let value reference = Expr.column reference value_column
end

module Directory = struct
  type row

  let table : row Table.t = Table.v_exn "recursive_directories"
  let id_column = Column.v_exn table "id" Db_type.int
  let parent_id_column = Column.nullable_v_exn table "parent_id" Db_type.int
  let label_column = Column.v_exn table "label" Db_type.text
  let id row = Expr.column row id_column
  let parent_id row = Expr.column row parent_id_column
  let label row = Expr.column row label_column
end

let directory_tree_fields id parent_id label depth =
  Derived_table.Fields.both
    (Derived_table.Fields.both
       (Derived_table.Fields.expr id)
       (Derived_table.Fields.expr parent_id))
    (Derived_table.Fields.both
       (Derived_table.Fields.expr label)
       (Derived_table.Fields.expr depth))
;;

let directory_tree_query =
  let anchor =
    Query.(
      from Directory.table
      |> where (fun directory -> Expr.is_null (Directory.parent_id directory))
      |> select_relation (fun directory ->
        directory_tree_fields
          (Directory.id directory)
          (Directory.parent_id directory)
          (Directory.label directory)
          (Expr.constant Db_type.int 0)))
  in
  let definition =
    Cte.recursive_relation ~union:`Union_all ~anchor ~step:(fun tree ->
      Query.(
        from Directory.table
        |> inner_join_cte_relation tree ~on:(fun directory ((parent_id, _), _) ->
          Directory.parent_id directory =. Expr.to_nullable parent_id)
        |> select_relation (fun (directory, ((_, _), (_, depth))) ->
          directory_tree_fields
            (Directory.id directory)
            (Directory.parent_id directory)
            (Directory.label directory)
            Expr.Int.Infix.(depth +. Expr.constant Db_type.int 1))))
  in
  Cte.with_result definition ~f:(fun tree ->
    Query.(
      from_cte_relation tree
      |> order_by (fun ((_, _), (_, depth)) -> depth) `Asc
      |> order_by (fun ((id, _), _) -> id) `Asc
      |> select (fun ((id, parent_id), (label, depth)) ->
        Projection.both
          (Projection.both (Projection.expr id) (Projection.expr parent_id))
          (Projection.both (Projection.expr label) (Projection.expr depth)))))
;;

let literal_recursive_numbers_query =
  let definition =
    Cte.recursive_relation
      ~union:`Union_all
      ~anchor:(Query.select_one_relation (Expr.constant Db_type.int 1))
      ~step:(fun numbers ->
        Query.(
          from_cte_relation numbers
          |> where (fun value -> value <$ 5)
          |> select_relation (fun value ->
            Derived_table.Fields.expr
              Expr.Int.Infix.(value +. Expr.constant Db_type.int 1))))
  in
  Cte.with_result definition ~f:(fun numbers ->
    Query.(from_cte_relation numbers |> select Projection.expr))
;;

type person_lookup =
  { person_id : int64
  ; maximum_rows : int
  }

let person_lookup_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let%map.Parameters person_id =
      params.column ~name:"person_id" Person.id_column ~get:(fun input -> input.person_id)
    and maximum_rows =
      params.non_negative_int ~name:"maximum_rows" ~get:(fun input -> input.maximum_rows)
    in
    params.query_many
      Query.(
        from Person.table
        |> where (fun person ->
          Person.id person >=. person_id &&. (Person.id person <=. person_id))
        |> limit_param maximum_rows
        |> select Person.projection))
;;

module Department = struct
  type row

  let table : row Table.t = Table.v_exn "departments"
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let person_id reference = Expr.column reference person_id_column
  let name reference = Expr.column reference name_column
  let nullable_name reference = Expr.nullable_column reference name_column
end

module Event = struct
  type row

  let table : row Table.t = Table.v_exn "events"
  let id_column = Column.v_exn table "id" Db_type.int64
  let occurred_at_column = Column.v_exn table "occurred_at" Db_type.timestamp
  let id reference = Expr.column reference id_column
  let occurred_at reference = Expr.column reference occurred_at_column
end

module Deferred_child = struct
  type row

  let table : row Table.t = Table.v_exn "deferred_children"
  let id_column = Column.v_exn table "id" Db_type.int64
end

module Calendar_day = struct
  type row

  let table : row Table.t = Table.v_exn "calendar_days"
  let id_column = Column.v_exn table "id" Db_type.int64
  let date_column = Column.v_exn table "calendar_date" Db_type.date
  let date reference = Expr.column reference date_column
end

module Resource = struct
  type row

  let table : row Table.t = Table.v_exn "resources"
  let id_column = Column.v_exn table "id" Db_type.int64
  let external_id_column = Column.v_exn table "external_id" Db_type.uuid
  let external_id reference = Expr.column reference external_id_column
end

module Large_number = struct
  type row

  let table : row Table.t = Table.v_exn "multiset_numbers"
  let value_column = Column.v_exn table "value" Db_type.int64
  let value reference = Expr.column reference value_column
end

module Codec_value = struct
  type row

  type t =
    { boolean : bool
    ; integer : int
    ; integer_64 : int64
    ; floating : float
    ; text : string
    ; bytes : bytes
    ; nullable_text : string option
    }

  let table : row Table.t = Table.v_exn "codec_values"
  let boolean_column = Column.v_exn table "boolean" Db_type.bool
  let integer_column = Column.v_exn table "integer_value" Db_type.int
  let integer_64_column = Column.v_exn table "integer_64" Db_type.int64
  let floating_column = Column.v_exn table "floating" Db_type.float
  let text_column = Column.v_exn table "text_value" Db_type.text
  let bytes_column = Column.v_exn table "bytes_value" Db_type.bytes
  let nullable_text_column = Column.nullable_v_exn table "nullable_text" Db_type.text

  let equal left right =
    Bool.equal left.boolean right.boolean
    && Int.(left.integer = right.integer)
    && Int64.(left.integer_64 = right.integer_64)
    && Float.(left.floating = right.floating)
    && String.equal left.text right.text
    && Bytes.equal left.bytes right.bytes
    && Option.equal String.equal left.nullable_text right.nullable_text
  ;;

  let projection reference =
    let open Projection.Let_syntax in
    let%map boolean = Projection.expr (Expr.column reference boolean_column)
    and integer = Projection.expr (Expr.column reference integer_column)
    and integer_64 = Projection.expr (Expr.column reference integer_64_column)
    and floating = Projection.expr (Expr.column reference floating_column)
    and text = Projection.expr (Expr.column reference text_column)
    and bytes = Projection.expr (Expr.column reference bytes_column)
    and nullable_text = Projection.expr (Expr.column reference nullable_text_column) in
    { boolean; integer; integer_64; floating; text; bytes; nullable_text }
  ;;
end

module Mapped_failure = struct
  type row

  let encode_type =
    Db_type.map
      ~name:"rejecting_encode"
      ~encode:(fun _ -> Error "encode rejected by test codec")
      ~decode:Result.return
      Db_type.text
  ;;

  let decode_type =
    Db_type.map
      ~name:"rejecting_decode"
      ~encode:Result.return
      ~decode:(fun _ -> Error "decode rejected by test codec")
      Db_type.text
  ;;

  let table : row Table.t = Table.v_exn "mapped_failures"
  let encode_column = Column.v_exn table "encoded" encode_type
  let decode_column = Column.v_exn table "decoded" decode_type
  let decoded reference = Expr.column reference decode_column
end

let direct sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit)
    (fun _ -> T.Query.parse sql)
;;

let adapter_or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Typed_sql_caqti_lwt.error_to_string error)
;;

let direct_string sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.string)
    (fun _ -> T.Query.parse sql)
;;

let direct_int64 sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.int64)
    (fun _ -> T.Query.parse sql)
;;

let equal_pair equal_left equal_right (left_a, left_b) (right_a, right_b) =
  equal_left left_a right_a && equal_right left_b right_b
;;

let equal_triple
      equal_first
      equal_second
      equal_third
      (left_a, left_b, left_c)
      (right_a, right_b, right_c)
  =
  equal_first left_a right_a && equal_second left_b right_b && equal_third left_c right_c
;;

let assert_equal ~equal expected actual =
  if not (List.equal equal expected actual) then
    failwith
      ("assertion failed: expected "
       ^ Int.to_string (List.length expected)
       ^ " rows, got "
       ^ Int.to_string (List.length actual))
;;

let assert_codec_error expected = function
  | Error (Typed_sql_caqti_lwt.Codec message) ->
    if not (String.equal expected message) then
      failwith ("unexpected codec error: " ^ message)
  | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
  | Ok _ -> failwith "expected a codec error"
;;

let profiler_test () =
  let module Profile = Typed_sql_caqti_lwt.Profile in
  let profiler = Typed_sql_caqti_lwt.Profiler.create ~max_shapes:2 () in
  let event
        ?(name = "people.list")
        ?(fingerprint = "shape-a")
        ?(outcome = Profile.Succeeded)
        ~prepare
        ~total
        ()
    : Profile.event
    =
    { name = Some name
    ; operation = Profile.Fetch
    ; dialect = Some Dialect.Sqlite
    ; fingerprint = Some fingerprint
    ; parameter_count = Some 1
    ; row_count = Some 2
    ; outcome
    ; durations =
        { prepare = Some prepare; database = Some 0.5; decode = Some 0.01; total }
    }
  in
  let observe = Typed_sql_caqti_lwt.Profiler.observer profiler in
  observe (event ~prepare:0.1 ~total:1. ());
  observe (event ~outcome:(Profile.Failed Profile.Database) ~prepare:0.2 ~total:1.2 ());
  observe (event ~fingerprint:"shape-b" ~prepare:0.05 ~total:0.8 ());
  observe (event ~name:"other" ~fingerprint:"shape-c" ~prepare:1. ~total:3. ());
  let snapshot = Typed_sql_caqti_lwt.Profiler.snapshot profiler in
  (match
     List.find snapshot.entries ~f:(fun entry ->
       Option.equal String.equal entry.fingerprint (Some "shape-a"))
   with
   | Some entry ->
     if
       not
         (Int.(entry.calls = 2)
          && Int.(entry.failures = 1)
          && Int.(entry.rows = 4)
          && Float.(entry.prepare_seconds > 0.29)
          && Float.(entry.max_total_seconds > 1.19))
     then
       failwith "profiler aggregated an event incorrectly"
   | None -> failwith "profiler omitted ordinary executions");
  (match
     List.find snapshot.entries ~f:(fun entry ->
       Option.equal String.equal entry.fingerprint (Some "shape-b"))
   with
   | Some entry when Int.(entry.calls = 1) -> ()
   | Some _ -> failwith "profiler aggregated a shape incorrectly"
   | None -> failwith "profiler merged distinct shapes");
  if not Int.(snapshot.overflow_calls = 1) then
    failwith "profiler did not bound shape cardinality";
  let report = Stdlib.Format.asprintf "%a" Typed_sql_caqti_lwt.Profiler.pp snapshot in
  if not (String.is_substring report ~substring:"people.list") then
    failwith "profiler report omitted the query name";
  let cleared = Typed_sql_caqti_lwt.Profiler.snapshot_and_reset profiler in
  if not Int.(List.length cleared.entries = 2) then
    failwith "snapshot_and_reset returned the wrong snapshot";
  let empty = Typed_sql_caqti_lwt.Profiler.snapshot profiler in
  if not (List.is_empty empty.entries && Int.(empty.overflow_calls = 0)) then
    failwith "snapshot_and_reset did not clear the profiler"
;;

let run conn =
  profiler_test ();
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL, role TEXT NOT NULL, nickname TEXT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE resources (id INTEGER PRIMARY KEY, external_id UUID NOT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec (direct "CREATE TABLE multiset_numbers (value INTEGER NOT NULL)") ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE departments (person_id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE codec_values (boolean INTEGER NOT NULL, integer_value INTEGER NOT NULL, integer_64 INTEGER NOT NULL, floating REAL NOT NULL, text_value TEXT NOT NULL, bytes_value BLOB NOT NULL, nullable_text TEXT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE mapped_failures (encoded TEXT NOT NULL, decoded TEXT NOT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE events (id INTEGER PRIMARY KEY, occurred_at TIMESTAMP NOT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE calendar_days (id INTEGER PRIMARY KEY, calendar_date DATE NOT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () = Connection.exec (direct "PRAGMA foreign_keys = ON") () |> caqti_or_fail in
  let* () =
    Connection.exec (direct "CREATE TABLE deferred_parents (id INTEGER PRIMARY KEY)") ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE deferred_children (id INTEGER REFERENCES deferred_parents (id) DEFERRABLE INITIALLY DEFERRED)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct "INSERT INTO departments (person_id, name) VALUES (1, 'Mathematics')")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "INSERT INTO people (id, name, role, nickname) VALUES (1, 'Ada', 'admin', NULL), (2, 'Grace', 'guest', 'Amazing Grace'), (3, 'Linus', 'admin', 'Lin')")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec (direct "CREATE TABLE cross_join_left (value INTEGER NOT NULL)") ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec (direct "CREATE TABLE cross_join_right (value INTEGER NOT NULL)") ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec (direct "CREATE TABLE cross_join_empty (value INTEGER NOT NULL)") ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec (direct "INSERT INTO cross_join_left (value) VALUES (1), (2)") ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct "INSERT INTO cross_join_right (value) VALUES (10), (20), (30)")
      ()
    |> caqti_or_fail
  in
  let cross_product =
    Query.(
      from Cross_left.table
      |> cross_join Cross_right.table
      |> order_by (fun (left, _right) -> Cross_left.value left) `Asc
      |> order_by (fun (_left, right) -> Cross_right.value right) `Asc
      |> select (fun (left, right) ->
        Projection.pair (Cross_left.value left) (Cross_right.value right)))
  in
  let* cross_product =
    Typed_sql_caqti_lwt.fetch ~conn cross_product >>= adapter_or_fail
  in
  let equal_cross_pair (left_value, right_value) (expected_left, expected_right) =
    Int.equal left_value expected_left && Int.equal right_value expected_right
  in
  if
    not
      (List.equal
         equal_cross_pair
         cross_product
         [ 1, 10; 1, 20; 1, 30; 2, 10; 2, 20; 2, 30 ])
  then
    failwith "CROSS JOIN did not return the Cartesian product";
  let empty_cross_product =
    Query.(
      from Cross_empty.table
      |> cross_join Cross_right.table
      |> select (fun (left, right) ->
        Projection.pair (Cross_empty.value left) (Cross_right.value right)))
  in
  let* empty_rows =
    Typed_sql_caqti_lwt.fetch ~conn empty_cross_product >>= adapter_or_fail
  in
  if not (List.is_empty empty_rows) then
    failwith "CROSS JOIN with an empty source returned rows";
  let optional_id_statement =
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      Parameters.map (params.optional_expr Db_type.int64 ~get:Fn.id) ~f:(fun id ->
        params.query_many
          Query.(
            from Person.table
            |> where_optional_param id ~f:(fun person id -> Person.id person =. id)
            |> order_by Person.id `Asc
            |> select (fun person -> Projection.expr (Person.id person)))))
  in
  let* all_ids = Adapter.run ~conn optional_id_statement None >>= adapter_or_fail in
  if not (List.equal Int64.equal all_ids [ 1L; 2L; 3L ]) then
    failwith "absent optional ID did not disable the SQLite predicate";
  let* matching_ids =
    Adapter.run ~conn optional_id_statement (Some 2L) >>= adapter_or_fail
  in
  if not (List.equal Int64.equal matching_ids [ 2L ]) then
    failwith "present optional ID did not filter SQLite rows";
  let* dialect_choice_rows =
    Adapter.run ~conn dialect_choice_statement { id = 1L; name = "Grace" }
    >>= adapter_or_fail
  in
  if not (List.equal String.equal dialect_choice_rows [ "Grace" ]) then
    failwith "SQLite did not select the SQLite statement branch";
  let value_table : unit Table.t = Table.v_exn "selected_ids" in
  let value_id = Column.v_exn value_table "id" Db_type.int64 in
  let selected_ids =
    Values.create
      ~table:value_table
      ~columns:(fun selected -> Projection.expr (Expr.column selected value_id))
      ~first:(Values.Row.expr (Expr.constant Db_type.int64 1L))
      ~rest:[ Values.Row.expr (Expr.constant Db_type.int64 3L) ]
  in
  let joined_values =
    Query.(
      from Person.table
      |> inner_join_values selected_ids ~on:(fun person selected ->
        Person.id person =. Expr.column selected value_id)
      |> order_by (fun (person, _selected) -> Person.id person) `Asc
      |> select (fun (person, _selected) -> Projection.expr (Person.name person)))
  in
  let* joined_names = Typed_sql_caqti_lwt.fetch ~conn joined_values >>= adapter_or_fail in
  if not (List.equal String.equal joined_names [ "Ada"; "Linus" ]) then
    failwith "VALUES join returned unexpected SQLite rows";
  let left_joined_values =
    Query.(
      from Person.table
      |> left_join_values selected_ids ~on:(fun person selected ->
        Person.id person =. Expr.column selected value_id)
      |> order_by (fun (person, _selected) -> Person.id person) `Asc
      |> select (fun (person, selected) ->
        Projection.pair (Person.name person) (Expr.nullable_column selected value_id)))
  in
  let* nullable_ids =
    Typed_sql_caqti_lwt.fetch ~conn left_joined_values >>= adapter_or_fail
  in
  let equal_row (left_name, left_id) (right_name, right_id) =
    String.equal left_name right_name && Option.equal Int64.equal left_id right_id
  in
  if
    not
      (List.equal
         equal_row
         nullable_ids
         [ "Ada", Some 1L; "Grace", None; "Linus", Some 3L ])
  then
    failwith "LEFT JOIN VALUES did not null-extend unmatched rows";
  let* () =
    Connection.exec
      (direct "INSERT INTO multiset_numbers (value) VALUES (9223372036854775807)")
      ()
    |> caqti_or_fail
  in
  let scalar_name person_id =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ person_id)
      |> limit 1
      |> select_scalar Person.name)
  in
  let run_fallback nullable =
    let query =
      Query.select_one
        (Expr.coalesce nullable ~default:(Expr.constant Db_type.text "unknown"))
    in
    let statement = Statement.query_one ~dialect:Dialect.portable query in
    Adapter.run ~conn statement () >>= adapter_or_fail
  in
  let* present = run_fallback (Expr.scalar_subquery (scalar_name 1L)) in
  if not (String.equal present "Ada") then
    failwith "COALESCE changed a present scalar value";
  let* absent = run_fallback (Expr.scalar_subquery (scalar_name 99L)) in
  if not (String.equal absent "unknown") then
    failwith "COALESCE did not replace an absent scalar row";
  let nullable_name =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 1L)
      |> limit 1
      |> select_scalar Person.nickname)
  in
  let* null_value = run_fallback (Expr.scalar_subquery_nullable nullable_name) in
  if not (String.equal null_value "unknown") then
    failwith "COALESCE did not replace a SQL NULL";
  let source_free_union =
    Query.union_all
      (Query.select_one (Expr.constant Db_type.int64 1L))
      (Query.select_one (Expr.constant Db_type.int64 2L))
  in
  let* union_rows =
    Typed_sql_caqti_lwt.fetch ~conn source_free_union >>= adapter_or_fail
  in
  if not (List.equal Int64.equal (List.sort union_rows ~compare:Int64.compare) [ 1L; 2L ])
  then
    failwith "source-free UNION ALL returned unexpected rows";
  let source_free_relation =
    Derived_table.create
      ~table:Person.table
      ~columns:(fun person -> Projection.expr (Person.id person))
      (Query.select_one (Expr.constant Db_type.int64 7L))
  in
  let source_free_cte = Cte.select source_free_relation in
  let source_free_cte_query =
    Cte.with_result source_free_cte ~f:(fun person ->
      let value = Query.(from_cte person |> limit 1 |> select_scalar Person.id) in
      Query.select_one
        (Expr.coalesce
           (Expr.scalar_subquery value)
           ~default:(Expr.constant Db_type.int64 0L)))
  in
  let statement = Statement.query_one ~dialect:Dialect.portable source_free_cte_query in
  let* cte_value = Adapter.run ~conn statement () >>= adapter_or_fail in
  if not (Int64.equal cte_value 7L) then
    failwith "source-free SELECT lost its CTE";
  let query =
    Query.(
      from Person.table
      |> where (fun person ->
        Person.id person
        >$ 0L
        &&. (Person.role person =$ `Admin)
        &&. (Person.name person =~$ "%d%"))
      |> order_by (fun person -> Person.id person) `Asc
      |> select Person.projection)
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn query >>= adapter_or_fail in
  assert_equal
    ~equal:Person.equal
    [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None } ]
    rows;
  let all_people =
    Query.(from Person.table |> order_by Person.id `Asc |> select Person.projection)
  in
  let collected_people =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 1L)
      |> limit_one
      |> select (fun _ -> Query.multiset all_people))
  in
  let* collected_people =
    Typed_sql_caqti_lwt.fetch_opt ~conn collected_people >>= adapter_or_fail
  in
  (match collected_people with
   | Some people ->
     assert_equal
       ~equal:Person.equal
       [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None }
       ; { Person.id = 2L
         ; name = "Grace"
         ; role = `Guest
         ; nickname = Some "Amazing Grace"
         }
       ; { Person.id = 3L; name = "Linus"; role = `Admin; nickname = Some "Lin" }
       ]
       people
   | None -> failwith "multiset wrapper returned no row");
  let empty_people =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 99L)
      |> select Person.projection)
  in
  let collected_empty =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 1L)
      |> limit_one
      |> select (fun _ -> Query.multiset empty_people))
  in
  let* collected_empty =
    Typed_sql_caqti_lwt.fetch_opt ~conn collected_empty >>= adapter_or_fail
  in
  (match collected_empty with
   | Some [] -> ()
   | Some _ -> failwith "empty multiset returned elements"
   | None -> failwith "empty multiset wrapper returned no row");
  let aggregated_people =
    Query.(
      from Person.table
      |> select_exactly_one (fun person ->
        Projection.multiset_agg
          ~filter:(Person.id person >$ 1L)
          ~order_by:[ Aggregate_order.desc (Person.id person) ]
          (Person.projection person)))
  in
  let* aggregated_people =
    Typed_sql_caqti_lwt.fetch_one ~conn aggregated_people >>= adapter_or_fail
  in
  assert_equal
    ~equal:Person.equal
    [ { Person.id = 3L; name = "Linus"; role = `Admin; nickname = Some "Lin" }
    ; { Person.id = 2L; name = "Grace"; role = `Guest; nickname = Some "Amazing Grace" }
    ]
    aggregated_people;
  let nested_collections =
    Query.(
      from Person.table
      |> select_exactly_one (fun person ->
        let departments =
          Query.(
            from Department.table
            |> where (fun department ->
              Department.person_id department =. Person.id person)
            |> order_by Department.name `Asc
            |> select (fun department -> Projection.expr (Department.name department)))
        in
        Projection.multiset_agg
          ~order_by:[ Aggregate_order.asc (Person.id person) ]
          (Projection.both
             (Projection.expr (Person.name person))
             (Query.multiset departments))))
  in
  let* nested_collections =
    Typed_sql_caqti_lwt.fetch_one ~conn nested_collections >>= adapter_or_fail
  in
  assert_equal
    ~equal:(equal_pair String.equal (List.equal String.equal))
    [ "Ada", [ "Mathematics" ]; "Grace", []; "Linus", [] ]
    nested_collections;
  let expect_multiset_codec_error column expected =
    let query =
      Query.(
        from Person.table
        |> select_exactly_one (fun person ->
          Projection.multiset_agg (Projection.expr (Expr.column person column))))
    in
    let* result = Typed_sql_caqti_lwt.fetch_one ~conn query in
    assert_codec_error ("multiset element 1.1: " ^ expected) result;
    Lwt.return_unit
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "name" Db_type.bool)
      "expected bool, got string"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "nickname" Db_type.bool)
      "expected bool, got null"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "name" Db_type.int)
      "expected int, got string"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "name" Db_type.int64)
      "expected int64, got string"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "name" Db_type.float)
      "expected float, got string"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "id" Db_type.text)
      "expected text, got number"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "name" Db_type.date)
      "expected date, got Ada"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "name" Db_type.timestamp)
      "expected timestamp, got Ada"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "name" Db_type.uuid)
      "expected uuid, got Ada"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "id" Db_type.date)
      "expected date, got number"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "id" Db_type.timestamp)
      "expected timestamp, got number"
  in
  let* () =
    expect_multiset_codec_error
      (Column.v_exn Person.table "id" Db_type.uuid)
      "expected uuid, got number"
  in
  let constant_collection =
    Query.(
      from Person.table
      |> select_exactly_one (fun person ->
        Projection.multiset_agg
          ~order_by:[ Aggregate_order.asc (Person.id person) ]
          (Projection.map2
             (Projection.return "person")
             (Projection.expr (Person.name person))
             ~f:(fun label name -> label, name))))
  in
  let* constant_collection =
    Typed_sql_caqti_lwt.fetch_one ~conn constant_collection >>= adapter_or_fail
  in
  assert_equal
    ~equal:(equal_pair String.equal String.equal)
    [ "person", "Ada"; "person", "Grace"; "person", "Linus" ]
    constant_collection;
  let false_collection =
    Query.(
      from Person.table
      |> select_exactly_one (fun _ ->
        Projection.multiset_agg (Projection.expr (Expr.constant Db_type.bool false))))
  in
  let* false_collection =
    Typed_sql_caqti_lwt.fetch_one ~conn false_collection >>= adapter_or_fail
  in
  if not (List.equal Bool.equal false_collection [ false; false; false ]) then
    failwith "false multiset values changed";
  let large_numbers =
    Query.(
      from Large_number.table
      |> select_exactly_one (fun number ->
        Projection.multiset_agg (Projection.expr (Large_number.value number))))
  in
  let* large_numbers =
    Typed_sql_caqti_lwt.fetch_one ~conn large_numbers >>= adapter_or_fail
  in
  if not (List.equal Int64.equal large_numbers [ Int64.max_value ]) then
    failwith "large int64 multiset value changed";
  let large_int = Column.v_exn Large_number.table "value" Db_type.int in
  let large_int_query =
    Query.(
      from Large_number.table
      |> select_exactly_one (fun number ->
        Projection.multiset_agg (Projection.expr (Expr.column number large_int))))
  in
  let* large_int_error = Typed_sql_caqti_lwt.fetch_one ~conn large_int_query in
  (match large_int_error with
   | Error (Typed_sql_caqti_lwt.Codec _) -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "oversized int unexpectedly decoded");
  let large_float = Column.v_exn Large_number.table "value" Db_type.float in
  let large_float_query =
    Query.(
      from Large_number.table
      |> select_exactly_one (fun number ->
        Projection.multiset_agg (Projection.expr (Expr.column number large_float))))
  in
  let* large_floats =
    Typed_sql_caqti_lwt.fetch_one ~conn large_float_query >>= adapter_or_fail
  in
  if Int.(List.length large_floats <> 1) then
    failwith "large float multiset returned the wrong row count";
  let integer_float = Column.v_exn Person.table "id" Db_type.float in
  let integer_float_query =
    Query.(
      from Person.table
      |> select_exactly_one (fun person ->
        Projection.multiset_agg
          ~order_by:[ Aggregate_order.asc (Person.id person) ]
          (Projection.expr (Expr.column person integer_float))))
  in
  let* integer_floats =
    Typed_sql_caqti_lwt.fetch_one ~conn integer_float_query >>= adapter_or_fail
  in
  if not (List.equal Float.equal integer_floats [ 1.; 2.; 3. ]) then
    failwith "integer JSON values did not decode as floats";
  let active_people =
    Derived_table.create
      ~table:Selected_person.table
      ~columns:Selected_person.projection
      Query.(
        from Person.table
        |> where (fun person -> Person.role person =$ `Admin)
        |> select (fun person -> Projection.pair (Person.id person) (Person.name person)))
  in
  let derived_people =
    Query.(
      from_derived active_people
      |> order_by (fun person -> Selected_person.id person) `Asc
      |> select Selected_person.projection)
  in
  let* derived_people =
    Typed_sql_caqti_lwt.fetch ~conn derived_people >>= adapter_or_fail
  in
  assert_equal
    ~equal:(equal_pair Int64.equal String.equal)
    [ 1L, "Ada"; 3L, "Linus" ]
    derived_people;
  let inferred_people =
    Query.(
      from Person.table
      |> where (fun person -> Person.role person =$ `Admin)
      |> select_relation (fun person ->
        Derived_table.Fields.both
          (Derived_table.Fields.expr (Person.id person))
          (Derived_table.Fields.expr (Person.name person))))
  in
  let inferred_people =
    Query.(
      from_relation inferred_people
      |> order_by (fun (id, _name) -> id) `Asc
      |> select (fun (id, name) -> Projection.pair id name))
  in
  let* inferred_people =
    Typed_sql_caqti_lwt.fetch ~conn inferred_people >>= adapter_or_fail
  in
  assert_equal
    ~equal:(equal_pair Int64.equal String.equal)
    [ 1L, "Ada"; 3L, "Linus" ]
    inferred_people;
  let largest_admin =
    Query.(
      from Person.table
      |> where (fun person -> Person.role person =$ `Admin)
      |> order_by (fun person -> Person.id person) `Desc
      |> limit 1
      |> select (fun person -> Projection.expr (Person.id person)))
  in
  let largest_guest =
    Query.(
      from Person.table
      |> where (fun person -> Person.role person =$ `Guest)
      |> order_by (fun person -> Person.id person) `Desc
      |> limit 1
      |> select (fun person -> Projection.expr (Person.id person)))
  in
  let* set_operation_rows =
    Typed_sql_caqti_lwt.fetch ~conn (Query.union_all largest_admin largest_guest)
    >>= adapter_or_fail
  in
  let set_operation_rows = List.sort set_operation_rows ~compare:Int64.compare in
  if not (List.equal Int64.equal set_operation_rows [ 2L; 3L ]) then
    failwith "UNION ALL did not preserve local branch limits";
  let active_people_cte = Cte.select active_people in
  let cte_people =
    Cte.with_result active_people_cte ~f:(fun people ->
      Query.(
        from_cte people
        |> order_by (fun person -> Selected_person.id person) `Asc
        |> select Selected_person.projection))
  in
  let* cte_people = Typed_sql_caqti_lwt.fetch ~conn cte_people >>= adapter_or_fail in
  assert_equal
    ~equal:(equal_pair Int64.equal String.equal)
    [ 1L, "Ada"; 3L, "Linus" ]
    cte_people;
  let numbers_relation query =
    Derived_table.create
      ~table:Number.table
      ~columns:(fun number -> Projection.expr (Number.value number))
      query
  in
  let recursive_start =
    Values.create
      ~table:value_table
      ~columns:(fun selected -> Projection.expr (Expr.column selected value_id))
      ~first:(Values.Row.expr (Expr.constant Db_type.int64 1L))
      ~rest:[]
  in
  let recursive_numbers =
    Cte.recursive
      ~union:`Union_all
      ~anchor:
        (numbers_relation
           Query.(
             from_values recursive_start
             |> select (fun selected -> Projection.expr (Expr.column selected value_id))))
      ~step:(fun numbers ->
        numbers_relation
          Query.(
            from_cte numbers
            |> where (fun number -> Number.value number <$ 4L)
            |> select (fun number ->
              let open Expr.Int64.Infix in
              Projection.expr (Number.value number +. Expr.constant Db_type.int64 1L))))
  in
  let recursive_numbers =
    Cte.with_result recursive_numbers ~f:(fun numbers ->
      Query.(
        from_cte numbers
        |> order_by (fun number -> Number.value number) `Asc
        |> select (fun number -> Projection.expr (Number.value number))))
  in
  let* recursive_numbers =
    Typed_sql_caqti_lwt.fetch ~conn recursive_numbers >>= adapter_or_fail
  in
  if not (List.equal Int64.equal recursive_numbers [ 1L; 2L; 3L; 4L ]) then
    failwith "recursive CTE returned unexpected rows";
  let* literal_recursive_numbers =
    Typed_sql_caqti_lwt.fetch ~conn literal_recursive_numbers_query >>= adapter_or_fail
  in
  if not (List.equal Int.equal [ 1; 2; 3; 4; 5 ] literal_recursive_numbers) then
    failwith "source-free recursive CTE returned unexpected rows";
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE recursive_directories (id INTEGER PRIMARY KEY, parent_id INTEGER NULL, label TEXT NOT NULL)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "INSERT INTO recursive_directories (id, parent_id, label) VALUES (1, NULL, 'root'), (2, 1, 'left'), (3, 1, 'right'), (4, 2, 'leaf')")
      ()
    |> caqti_or_fail
  in
  let* directory_rows =
    Typed_sql_caqti_lwt.fetch ~conn directory_tree_query >>= adapter_or_fail
  in
  let equal_directory_row
        ((left_id, left_parent), (left_label, left_depth))
        ((right_id, right_parent), (right_label, right_depth))
    =
    Int.equal left_id right_id
    && Option.equal Int.equal left_parent right_parent
    && String.equal left_label right_label
    && Int.equal left_depth right_depth
  in
  assert_equal
    ~equal:equal_directory_row
    [ (1, None), ("root", 0)
    ; (2, Some 1), ("left", 1)
    ; (3, Some 1), ("right", 1)
    ; (4, Some 2), ("leaf", 2)
    ]
    directory_rows;
  let* () =
    Connection.exec (direct "DROP TABLE recursive_directories") () |> caqti_or_fail
  in
  let* lookup =
    Typed_sql_caqti_lwt.run
      ~conn
      person_lookup_statement
      { person_id = 1L; maximum_rows = 1 }
    >>= adapter_or_fail
  in
  assert_equal ~equal:Person.equal rows lookup;
  let* invalid_parameter =
    Typed_sql_caqti_lwt.run
      ~conn
      person_lookup_statement
      { person_id = 1L; maximum_rows = -1 }
  in
  (match invalid_parameter with
   | Error
       (Typed_sql_caqti_lwt.Parameter
          ({ name = Some name
           ; message = Typed_sql.Statement.Negative_pagination_value -1
           } as error)) ->
     assert (String.equal name "maximum_rows");
     assert (
       String.equal
         (Typed_sql_caqti_lwt.error_to_string (Typed_sql_caqti_lwt.Parameter error))
         "parameter maximum_rows must be non-negative, got -1")
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "negative runtime LIMIT reached SQLite");
  let many = Statement.query_many ~dialect:Dialect.portable query in
  let one = Statement.expect_one ~dialect:Dialect.portable query in
  let optional = Statement.expect_optional ~dialect:Dialect.portable query in
  let observed = ref None in
  let observer event = observed := Some event in
  let* profiled_rows =
    Typed_sql_caqti_lwt.run ~observer ~name:"people.admins" ~conn many ()
    >>= adapter_or_fail
  in
  assert_equal ~equal:Person.equal rows profiled_rows;
  (match !observed with
   | Some event ->
     if
       Option.is_none event.durations.prepare
       || Option.is_none event.durations.database
       || Option.is_none event.durations.decode
       || Option.is_none event.fingerprint
       || not (Option.equal String.equal event.name (Some "people.admins"))
     then
       failwith "profiled fetch omitted execution measurements"
   | None -> failwith "profiled fetch emitted no event");
  observed := None;
  let* compiled_rows =
    Typed_sql_caqti_lwt.run ~observer ~conn many () >>= adapter_or_fail
  in
  assert_equal ~equal:Person.equal rows compiled_rows;
  (match !observed with
   | Some _ -> ()
   | None -> failwith "compiled fetch emitted no event");
  let* compiled_row = Typed_sql_caqti_lwt.run ~conn one () >>= adapter_or_fail in
  if Int64.(compiled_row.id <> 1L) then
    failwith "expect_one returned the wrong row";
  let* compiled_row =
    Typed_sql_caqti_lwt.run
      ~observer:(fun _ -> failwith "ignored observer failure")
      ~conn
      optional
      ()
    >>= adapter_or_fail
  in
  if Option.is_none compiled_row then
    failwith "expect_optional returned no row";
  let postgresql = Statement.query_many ~dialect:Dialect.postgresql query in
  let* mismatch = Typed_sql_caqti_lwt.run ~conn postgresql () in
  (match mismatch with
   | Error
       (Typed_sql_caqti_lwt.Dialect_mismatch
          { expected = Dialect.Postgresql; connection = Dialect.Sqlite }) -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "a PostgreSQL compiled query ran on SQLite");
  let postgresql_only =
    Query.(
      from Person.table
      |> Postgresql.Query.having (fun _ -> Condition.true_)
      |> select (fun _ -> Projection.expr Expr.count_all))
  in
  let postgresql_only =
    Statement.query_many ~dialect:Dialect.postgresql postgresql_only
  in
  let* specific_mismatch = Typed_sql_caqti_lwt.run ~conn postgresql_only () in
  (match specific_mismatch with
   | Error
       (Typed_sql_caqti_lwt.Dialect_mismatch
          { expected = Dialect.Postgresql; connection = Dialect.Sqlite }) -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "a PostgreSQL-specific query ran on SQLite");
  let postgresql_command =
    Statement.command
      ~dialect:Dialect.postgresql
      Delete.(
        from Person.table |> where (fun person -> Person.id person =$ -1L) |> command)
  in
  let* command_mismatch = Typed_sql_caqti_lwt.run ~conn postgresql_command () in
  (match command_mismatch with
   | Error
       (Typed_sql_caqti_lwt.Dialect_mismatch
          { expected = Dialect.Postgresql; connection = Dialect.Sqlite }) -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "a PostgreSQL compiled command ran on SQLite");
  let callback_calls = ref 0 in
  let dynamic_query =
    Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
      Int.incr callback_calls;
      Query.(from Person.table |> select Person.projection))
  in
  let* dynamic_query_mismatch = Typed_sql_caqti_lwt.run ~conn dynamic_query () in
  (match dynamic_query_mismatch with
   | Error
       (Typed_sql_caqti_lwt.Dialect_mismatch
          { expected = Dialect.Postgresql; connection = Dialect.Sqlite }) -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "a PostgreSQL dynamic query ran on SQLite");
  let dynamic_command =
    Statement.Dynamic.command ~dialect:Dialect.postgresql (fun () ->
      Int.incr callback_calls;
      Delete.(
        from Person.table |> where (fun person -> Person.id person =$ -1L) |> command))
  in
  let* dynamic_command_mismatch = Typed_sql_caqti_lwt.run ~conn dynamic_command () in
  (match dynamic_command_mismatch with
   | Error
       (Typed_sql_caqti_lwt.Dialect_mismatch
          { expected = Dialect.Postgresql; connection = Dialect.Sqlite }) -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "a PostgreSQL dynamic command ran on SQLite");
  assert (Int.(!callback_calls = 0));
  let no_op_delete =
    Delete.(from Person.table |> where (fun person -> Person.id person =$ -1L) |> command)
  in
  let compiled_delete = Statement.command ~dialect:Dialect.sqlite no_op_delete in
  let* _ = Typed_sql_caqti_lwt.run ~conn compiled_delete () >>= adapter_or_fail in
  let invalid_limit =
    Query.(from Person.table |> limit (-1) |> select Person.projection)
  in
  (match Statement.query_many ~dialect:Dialect.portable invalid_limit with
   | exception Statement.Definition_error { error = Compile_error.Negative_limit -1; _ }
     -> ()
   | exception Statement.Definition_error error ->
     failwith (Compile_error.to_string error.error)
   | _ -> failwith "negative LIMIT unexpectedly compiled");
  let raising_query =
    Query.(
      from Person.table
      |> limit 1
      |> select (fun person ->
        Projection.map
          ~f:(fun _ -> failwith "projection callback failed")
          (Projection.expr (Person.id person))))
  in
  observed := None;
  let* raised =
    Lwt.catch
      (fun () ->
         let* _ = Typed_sql_caqti_lwt.fetch_one ~observer ~conn raising_query in
         Lwt.return false)
      (function
        | Failure message when String.equal message "projection callback failed" ->
          Lwt.return true
        | error -> Lwt.fail error)
  in
  if not raised then
    failwith "projection exception was not preserved";
  (match !observed with
   | Some
       { outcome = Typed_sql_caqti_lwt.Profile.Failed Typed_sql_caqti_lwt.Profile.Raised
       ; durations = { decode = Some _; _ }
       ; _
       } -> ()
   | _ -> failwith "raised exception emitted the wrong profile event");
  let* row = Typed_sql_caqti_lwt.fetch_one ~conn query >>= adapter_or_fail in
  if Int64.(row.id <> 1L) then
    failwith "fetch_one returned the wrong row";
  let missing =
    Query.(
      from Person.table
      |> where (fun person -> Person.name person =$ "missing")
      |> select Person.projection)
  in
  let* missing = Typed_sql_caqti_lwt.fetch_opt ~conn missing >>= adapter_or_fail in
  if Option.is_some missing then
    failwith "fetch_opt unexpectedly returned a row";
  let empty_scalar =
    Query.(
      from Person.table
      |> select (fun _ ->
        Projection.expr
          (Expr.scalar_subquery
             Query.(
               from Department.table
               |> where (fun department -> Department.person_id department =$ 99L)
               |> limit 1
               |> select_scalar Department.name))))
  in
  let* empty_scalar = Typed_sql_caqti_lwt.fetch ~conn empty_scalar >>= adapter_or_fail in
  if not (List.for_all empty_scalar ~f:Option.is_none) then
    failwith "an empty scalar subquery did not decode as None";
  let nullable_scalar =
    Query.(
      from Person.table
      |> limit 1
      |> select (fun _ ->
        Projection.expr
          (Expr.scalar_subquery_nullable
             Query.(
               from Department.table
               |> limit 1
               |> select_scalar (fun department ->
                 Expr.to_nullable (Department.name department))))))
  in
  let* nullable_scalar =
    Typed_sql_caqti_lwt.fetch_one ~conn nullable_scalar >>= adapter_or_fail
  in
  if not (Option.equal String.equal nullable_scalar (Some "Mathematics")) then
    failwith "nullable scalar subquery decoded the wrong value";
  let empty_case =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 1L)
      |> select (fun person -> Projection.expr (Expr.case [] ~else_:(Person.name person))))
  in
  let* empty_case = Typed_sql_caqti_lwt.fetch_one ~conn empty_case >>= adapter_or_fail in
  if not (String.equal empty_case "Ada") then
    failwith "empty CASE did not evaluate its else expression";
  let injection = "'; DROP TABLE people; --" in
  let injected =
    Query.(
      from Person.table
      |> where (fun person -> Person.name person =$ injection)
      |> select Person.projection)
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn injected >>= adapter_or_fail in
  assert_equal ~equal:Person.equal [] rows;
  let all =
    Query.(
      from Person.table
      |> where_opt None ~f:(fun person name -> Person.name person =$ name)
      |> order_by (fun person -> Person.id person) `Asc
      |> select Person.projection)
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn all >>= adapter_or_fail in
  assert_equal
    ~equal:Person.equal
    [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None }
    ; { Person.id = 2L; name = "Grace"; role = `Guest; nickname = Some "Amazing Grace" }
    ; { Person.id = 3L; name = "Linus"; role = `Admin; nickname = Some "Lin" }
    ]
    rows;
  let departments =
    Query.(
      from Person.table
      |> left_join Department.table ~on:(fun person department ->
        Person.id person =. Department.person_id department)
      |> order_by (fun (person, _) -> Person.id person) `Asc
      |> select (fun (person, department) ->
        Projection.map2
          ~f:(fun person_name department_name -> person_name, department_name)
          (Projection.expr (Person.name person))
          (Projection.expr (Department.nullable_name department))))
  in
  let* departments = Typed_sql_caqti_lwt.fetch ~conn departments >>= adapter_or_fail in
  assert_equal
    ~equal:(equal_pair String.equal (Option.equal String.equal))
    [ "Ada", Some "Mathematics"; "Grace", None; "Linus", None ]
    departments;
  let applicative =
    Query.(
      from Person.table
      |> order_by (fun person -> Person.id person) `Asc
      |> select (fun person ->
        let open Projection.Let_syntax in
        let%map name = Projection.expr (Person.name person)
        and values =
          Projection.all
            [ Projection.expr (Expr.constant Db_type.int 11)
            ; Projection.apply
                (Projection.return Int.succ)
                (Projection.expr (Expr.constant Db_type.int 22))
            ]
        and empty = Projection.all [] in
        name, values, empty))
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn applicative >>= adapter_or_fail in
  assert_equal
    ~equal:(equal_triple String.equal (List.equal Int.equal) (List.equal Int.equal))
    [ "Ada", [ 11; 23 ], []; "Grace", [ 11; 23 ], []; "Linus", [ 11; 23 ], [] ]
    rows;
  let codec_value =
    { Codec_value.boolean = true
    ; integer = 7
    ; integer_64 = 8L
    ; floating = 1.25
    ; text = "typed"
    ; bytes = Bytes.of_string "\000\001\255"
    ; nullable_text = None
    }
  in
  let codec_insert =
    Insert.(
      into Codec_value.table
      |> set Codec_value.boolean_column codec_value.boolean
      |> set Codec_value.integer_column codec_value.integer
      |> set Codec_value.integer_64_column codec_value.integer_64
      |> set Codec_value.floating_column codec_value.floating
      |> set Codec_value.text_column codec_value.text
      |> set Codec_value.bytes_column codec_value.bytes
      |> set Codec_value.nullable_text_column codec_value.nullable_text
      |> returning Codec_value.projection)
  in
  let* decoded_codec =
    Typed_sql_caqti_lwt.fetch_one ~conn codec_insert >>= adapter_or_fail
  in
  if not (Codec_value.equal codec_value decoded_codec) then
    failwith "database type round-trip changed a value";
  let primitive_collection =
    Query.(
      from Codec_value.table
      |> select_exactly_one (fun value ->
        let open Projection.Let_syntax in
        Projection.multiset_agg
          (let%map boolean =
             Projection.expr (Expr.column value Codec_value.boolean_column)
           and integer = Projection.expr (Expr.column value Codec_value.integer_column)
           and integer_64 =
             Projection.expr (Expr.column value Codec_value.integer_64_column)
           and floating = Projection.expr (Expr.column value Codec_value.floating_column)
           and text = Projection.expr (Expr.column value Codec_value.text_column)
           and nullable_text =
             Projection.expr (Expr.column value Codec_value.nullable_text_column)
           in
           boolean, integer, integer_64, floating, text, nullable_text)))
  in
  let* primitive_collection =
    Typed_sql_caqti_lwt.fetch_one ~conn primitive_collection >>= adapter_or_fail
  in
  (match primitive_collection with
   | [ (boolean, integer, integer_64, floating, text, nullable_text) ] ->
     if
       not
         (Bool.equal boolean true
          && Int.equal integer 7
          && Int64.equal integer_64 8L
          && Float.equal floating 1.25
          && String.equal text "typed"
          && Option.is_none nullable_text)
     then
       failwith "primitive multiset codecs changed values"
   | _ -> failwith "primitive multiset returned the wrong row count");
  let inserted =
    Insert.(
      into Person.table
      |> set Person.id_column 4L
      |> set Person.name_column "Edsger"
      |> set Person.role_column `Guest
      |> set Person.nickname_column None
      |> returning Person.projection)
  in
  let* inserted = Typed_sql_caqti_lwt.fetch_one ~conn inserted >>= adapter_or_fail in
  if Int64.(inserted.id <> 4L) then
    failwith "INSERT RETURNING returned the wrong row";
  let update =
    Update.(
      table Person.table
      |> set Person.name_column "Dijkstra"
      |> where (fun person -> Person.id person =$ 4L)
      |> command)
  in
  let* affected = Typed_sql_caqti_lwt.execute ~conn update >>= adapter_or_fail in
  (match affected with
   | Affected_rows.Known 1 -> ()
   | Affected_rows.Known count ->
     failwith ("UPDATE affected " ^ Int.to_string count ^ " rows")
   | Affected_rows.Unknown -> ());
  let delete =
    Delete.(from Person.table |> where (fun person -> Person.id person =$ 4L) |> command)
  in
  let* _ = Typed_sql_caqti_lwt.execute ~conn delete >>= adapter_or_fail in
  let deleted =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 4L)
      |> select Person.projection)
  in
  let* deleted = Typed_sql_caqti_lwt.fetch_opt ~conn deleted >>= adapter_or_fail in
  if Option.is_some deleted then
    failwith "DELETE did not remove the row";
  let codec_encode_failure =
    Insert.(
      into Mapped_failure.table
      |> set Mapped_failure.encode_column "bad"
      |> set Mapped_failure.decode_column "ok"
      |> command)
  in
  observed := None;
  let* encode_failure =
    Typed_sql_caqti_lwt.execute ~observer ~conn codec_encode_failure
  in
  assert_codec_error "encode rejected by test codec" encode_failure;
  (match !observed with
   | Some
       { outcome = Typed_sql_caqti_lwt.Profile.Failed Typed_sql_caqti_lwt.Profile.Encode
       ; durations = { prepare = Some _; database = None; _ }
       ; _
       } -> ()
   | _ -> failwith "encode failure emitted the wrong profile event");
  let* () =
    Connection.exec
      (direct "INSERT INTO mapped_failures (encoded, decoded) VALUES ('ok', 'bad')")
      ()
    |> caqti_or_fail
  in
  let codec_decode_failure =
    Query.(
      from Mapped_failure.table
      |> select (fun row -> Projection.expr (Mapped_failure.decoded row)))
  in
  observed := None;
  let* decode_failure = Typed_sql_caqti_lwt.fetch ~observer ~conn codec_decode_failure in
  assert_codec_error "decode rejected by test codec" decode_failure;
  (match !observed with
   | Some
       { outcome = Typed_sql_caqti_lwt.Profile.Failed Typed_sql_caqti_lwt.Profile.Decode
       ; row_count = Some 1
       ; durations = { decode = Some _; _ }
       ; _
       } -> ()
   | _ -> failwith "decode failure emitted the wrong profile event");
  let* decode_failure = Typed_sql_caqti_lwt.fetch_one ~conn codec_decode_failure in
  assert_codec_error "decode rejected by test codec" decode_failure;
  let* decode_failure = Typed_sql_caqti_lwt.fetch_opt ~conn codec_decode_failure in
  assert_codec_error "decode rejected by test codec" decode_failure;
  let multiset_decode_failure =
    Query.(
      from Mapped_failure.table
      |> select_exactly_one (fun row ->
        Projection.multiset_agg (Projection.expr (Mapped_failure.decoded row))))
  in
  let* decode_failure = Typed_sql_caqti_lwt.fetch_one ~conn multiset_decode_failure in
  assert_codec_error "multiset element 1.1: decode rejected by test codec" decode_failure;
  let query_after_codec_failure =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 1L)
      |> select (fun person -> Projection.expr (Person.name person)))
  in
  let* name =
    Typed_sql_caqti_lwt.fetch_one ~conn query_after_codec_failure >>= adapter_or_fail
  in
  if not (String.equal name "Ada") then
    failwith "connection returned the wrong row after a codec error";
  let multi_row_insert =
    Insert.(
      rows
        Person.table
        [ (fun row ->
            row
            |> set Person.id_column 5L
            |> set Person.name_column "Barbara"
            |> set Person.role_column `Admin
            |> set Person.nickname_column (Some "Barb"))
        ; (fun row ->
            row
            |> set Person.role_column `Guest
            |> set Person.id_column 6L
            |> set Person.nickname_column None
            |> set Person.name_column "Margaret")
        ]
      |> returning Person.projection)
  in
  let* inserted = Typed_sql_caqti_lwt.fetch ~conn multi_row_insert >>= adapter_or_fail in
  assert_equal
    ~equal:Person.equal
    [ { Person.id = 5L; name = "Barbara"; role = `Admin; nickname = Some "Barb" }
    ; { Person.id = 6L; name = "Margaret"; role = `Guest; nickname = None }
    ]
    inserted;
  let conditional_update =
    Update.(
      table Person.table
      |> set_opt Person.name_column None
      |> set_opt Person.nickname_column (Some None)
      |> where (fun person -> Person.id person =$ 5L)
      |> command)
  in
  let* _ = Typed_sql_caqti_lwt.execute ~conn conditional_update >>= adapter_or_fail in
  let updated_person =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ 5L)
      |> select Person.projection)
  in
  let* updated_person =
    Typed_sql_caqti_lwt.fetch_one ~conn updated_person >>= adapter_or_fail
  in
  if
    not
      (String.equal updated_person.name "Barbara"
       && Option.is_none updated_person.nickname)
  then
    failwith "conditional UPDATE changed an omitted value or failed to write NULL";
  let update_from =
    Update.(
      table Person.table
      |> from Department.table ~f:(fun person department update ->
        update
        |> set_expr Person.name_column (Department.name department)
        |> where (fun _ -> Person.id person =. Department.person_id department))
      |> returning Person.projection)
  in
  let* updated_from =
    Typed_sql_caqti_lwt.fetch_one ~conn update_from >>= adapter_or_fail
  in
  if not (String.equal updated_from.name "Mathematics") then
    failwith "UPDATE FROM did not use the joined row";
  let expressions =
    Query.(
      from Person.table
      |> where (fun person ->
        Expr.in_exprs (Person.id person) [ Expr.constant Db_type.int64 1L ]
        &&. Expr.not_in_exprs (Person.id person) [ Expr.constant Db_type.int64 2L ]
        &&. Expr.between_exprs
              (Person.id person)
              ~lower:(Expr.constant Db_type.int64 1L)
              ~upper:(Expr.constant Db_type.int64 3L))
      |> select (fun person ->
        let open Expr.Int64.Infix in
        Projection.map3
          ~f:(fun label calculated length -> label, calculated, length)
          (Projection.expr
             (Expr.case
                [ Person.name person =$ "Ada", Expr.upper (Person.name person) ]
                ~else_:
                  (Expr.concat
                     (Expr.lower (Person.name person))
                     (Expr.constant Db_type.text "!"))))
          (Projection.expr
             ((Person.id person +. Expr.constant Db_type.int64 5L)
              *. Expr.constant Db_type.int64 2L))
          (Projection.expr (Expr.length (Person.name person)))))
  in
  let* expression_result =
    Typed_sql_caqti_lwt.fetch_one ~conn expressions >>= adapter_or_fail
  in
  if
    not
      (equal_triple
         String.equal
         Int64.equal
         Int.equal
         expression_result
         ("mathematics!", 12L, 11))
  then
    failwith "portable expression evaluation returned unexpected values";
  let counts =
    Query.(
      from Person.table
      |> select (fun person ->
        Projection.pair Expr.count_all (Expr.count_distinct (Person.role person))))
  in
  let* counts = Typed_sql_caqti_lwt.fetch_one ~conn counts >>= adapter_or_fail in
  if not (equal_pair Int64.equal Int64.equal counts (5L, 2L)) then
    failwith "aggregate counts returned unexpected values";
  let counts_by_role =
    Query.(
      from Person.table
      |> group_by (fun person -> Person.role person)
      |> having (fun _ -> Expr.count_all >$ 1L)
      |> order_by (fun person -> Person.role person) `Asc
      |> select (fun person -> Projection.pair (Person.role person) Expr.count_all))
  in
  let* counts_by_role =
    Typed_sql_caqti_lwt.fetch ~conn counts_by_role >>= adapter_or_fail
  in
  if
    not
      (List.equal
         (equal_pair Person.equal_role Int64.equal)
         counts_by_role
         [ `Admin, 3L; `Guest, 2L ])
  then
    failwith "GROUP BY returned unexpected values";
  let people_with_departments =
    Query.(
      from Person.table
      |> where (fun person ->
        Query.(
          from Department.table
          |> where (fun department -> Department.person_id department =. Person.id person)
          |> exists))
      |> select (fun person ->
        let department_name =
          Query.(
            from Department.table
            |> where (fun department ->
              Department.person_id department =. Person.id person)
            |> limit 1
            |> select_scalar Department.name)
          |> Expr.scalar_subquery
        in
        Projection.pair (Person.name person) department_name))
  in
  let* people_with_departments =
    Typed_sql_caqti_lwt.fetch ~conn people_with_departments >>= adapter_or_fail
  in
  if
    not
      (List.equal
         (equal_pair String.equal (Option.equal String.equal))
         people_with_departments
         [ "Mathematics", Some "Mathematics" ])
  then
    failwith "correlated subqueries returned unexpected values";
  let duplicate =
    Insert.(
      into Person.table
      |> set Person.id_column 1L
      |> set Person.name_column "Duplicate"
      |> set Person.role_column `Guest
      |> set Person.nickname_column None
      |> command)
  in
  observed := None;
  let* duplicate = Typed_sql_caqti_lwt.execute ~observer ~conn duplicate in
  (match duplicate with
   | Error (Typed_sql_caqti_lwt.Constraint_violation { kind = Other; _ }) -> ()
   | Error error ->
     failwith
       ("expected SQLite integrity error, got "
        ^ Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "duplicate primary key unexpectedly succeeded");
  (match !observed with
   | Some
       { outcome = Typed_sql_caqti_lwt.Profile.Failed Typed_sql_caqti_lwt.Profile.Database
       ; durations = { database = Some _; _ }
       ; _
       } -> ()
   | _ -> failwith "database failure emitted the wrong profile event");
  let ignored_duplicate =
    Insert.(
      into Person.table
      |> set Person.id_column 1L
      |> set Person.name_column "Ignored"
      |> set Person.role_column `Guest
      |> set Person.nickname_column None
      |> on_conflict_do_nothing
      |> command)
  in
  let* ignored =
    Typed_sql_caqti_lwt.execute ~conn ignored_duplicate >>= adapter_or_fail
  in
  (match ignored with
   | Affected_rows.Known 0 | Affected_rows.Unknown -> ()
   | Affected_rows.Known count ->
     failwith ("ON CONFLICT DO NOTHING affected " ^ Int.to_string count ^ " rows"));
  let upsert_person name =
    Insert.(
      into Person.table
      |> set Person.id_column 77L
      |> set Person.name_column name
      |> set Person.role_column `Guest
      |> set Person.nickname_column None
      |> on_conflict (Conflict_target.column Person.id_column)
      |> do_update (fun ~existing ~excluded ->
        Conflict_update.(
          empty
          |> set_expr
               Person.name_column
               (Expr.concat
                  (Person.name existing)
                  (Expr.concat (Expr.constant Db_type.text "/") (Person.name excluded)))
          |> set_expr Person.role_column (Person.role excluded)
          |> set_expr Person.nickname_column (Person.nickname excluded)))
      |> returning Person.projection)
  in
  let* inserted =
    Typed_sql_caqti_lwt.fetch_one ~conn (upsert_person "Before") >>= adapter_or_fail
  in
  if
    not
      (Person.equal
         inserted
         { Person.id = 77L; name = "Before"; role = `Guest; nickname = None })
  then
    failwith "UPSERT insert branch returned the wrong row";
  let* updated =
    Typed_sql_caqti_lwt.fetch_one ~conn (upsert_person "After") >>= adapter_or_fail
  in
  if
    not
      (Person.equal
         updated
         { Person.id = 77L; name = "Before/After"; role = `Guest; nickname = None })
  then
    failwith "UPSERT update branch returned the wrong row";
  let transaction_insert id name =
    Insert.(
      into Person.table
      |> set Person.id_column id
      |> set Person.name_column name
      |> set Person.role_column `Guest
      |> set Person.nickname_column None
      |> command)
  in
  let* rolled_back =
    Typed_sql_caqti_lwt.transaction ~conn ~f:(fun transaction_conn ->
      let* inserted =
        Typed_sql_caqti_lwt.execute
          ~conn:transaction_conn
          (transaction_insert 99L "Rollback")
      in
      match inserted with
      | Error error -> Lwt.return (Error error)
      | Ok _ -> Lwt.return (Error (Typed_sql_caqti_lwt.Codec "requested rollback")))
  in
  (match rolled_back with
   | Error (Typed_sql_caqti_lwt.Codec "requested rollback") -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok () -> failwith "transaction unexpectedly committed");
  let person_exists id =
    Query.(
      from Person.table
      |> where (fun person -> Person.id person =$ id)
      |> select (fun person -> Projection.expr (Person.id person)))
  in
  let* absent =
    Typed_sql_caqti_lwt.fetch_opt ~conn (person_exists 99L) >>= adapter_or_fail
  in
  if Option.is_some absent then
    failwith "failed transaction did not roll back";
  let* committed =
    Typed_sql_caqti_lwt.transaction ~conn ~f:(fun transaction_conn ->
      Typed_sql_caqti_lwt.execute ~conn:transaction_conn (transaction_insert 98L "Commit")
      |> Lwt.map (Result.map ~f:(fun _ -> ())))
  in
  (match committed with
   | Ok () -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error));
  let* present =
    Typed_sql_caqti_lwt.fetch_opt ~conn (person_exists 98L) >>= adapter_or_fail
  in
  if not (Option.value_map present ~default:false ~f:(Int64.equal 98L)) then
    failwith "successful transaction did not commit";
  let deferred_insert =
    Insert.(into Deferred_child.table |> set Deferred_child.id_column 999L |> command)
  in
  let* deferred_commit =
    Typed_sql_caqti_lwt.transaction ~conn ~f:(fun transaction_conn ->
      Typed_sql_caqti_lwt.execute ~conn:transaction_conn deferred_insert
      |> Lwt.map (Result.map ~f:(fun _ -> ())))
  in
  (match deferred_commit with
   | Error (Typed_sql_caqti_lwt.Constraint_violation { kind = Foreign_key; _ }) -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error)
   | Ok () -> failwith "deferred foreign key unexpectedly committed");
  let* reusable_after_failed_commit =
    Typed_sql_caqti_lwt.transaction ~conn ~f:(fun _ -> Lwt.return (Ok ()))
  in
  (match reusable_after_failed_commit with
   | Ok () -> ()
   | Error error -> failwith (Typed_sql_caqti_lwt.error_to_string error));
  let timestamp =
    match Ptime.of_rfc3339 "2024-01-02T03:04:05Z" with
    | Ok (value, _, _) -> value
    | Error _ -> failwith "invalid test timestamp"
  in
  let timestamp_insert =
    Insert.(
      into Event.table
      |> set Event.id_column 1L
      |> set Event.occurred_at_column timestamp
      |> returning (fun event -> Projection.expr (Event.occurred_at event)))
  in
  let* decoded_timestamp =
    Typed_sql_caqti_lwt.fetch_one ~conn timestamp_insert >>= adapter_or_fail
  in
  if not (Ptime.equal timestamp decoded_timestamp) then
    failwith "timestamp codec changed a bound value";
  let current_timestamp_insert =
    Insert.(
      into Event.table
      |> set Event.id_column 2L
      |> set_expr Event.occurred_at_column Expr.current_timestamp
      |> command)
  in
  let* _ =
    Typed_sql_caqti_lwt.execute ~conn current_timestamp_insert >>= adapter_or_fail
  in
  let timestamp_query =
    Query.(
      from Event.table
      |> where (fun event -> Event.occurred_at event <=. Expr.current_timestamp)
      |> order_by Event.id `Asc
      |> select (fun event -> Projection.expr (Event.id event)))
  in
  let* timestamp_ids =
    Typed_sql_caqti_lwt.fetch ~conn timestamp_query >>= adapter_or_fail
  in
  if not (List.equal Int64.equal timestamp_ids [ 1L; 2L ]) then
    failwith "CURRENT_TIMESTAMP comparison returned unexpected rows";
  let* () =
    Connection.exec
      (direct
         "INSERT INTO events (id, occurred_at) VALUES (3, '2024-01-02 04:04:05+01:00')")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct "INSERT INTO events (id, occurred_at) VALUES (4, '2024-01-02 03:04:05z')")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "INSERT INTO events (id, occurred_at) VALUES (5, '2024-01-02 02:04:05-01:00')")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct "INSERT INTO events (id, occurred_at) VALUES (6, '2024-01-02X03:04:05')")
      ()
    |> caqti_or_fail
  in
  let malformed_timestamp_collection =
    Query.(
      from Event.table
      |> where (fun event -> Event.id event =$ 6L)
      |> select_exactly_one (fun event ->
        Projection.multiset_agg (Projection.expr (Event.occurred_at event))))
  in
  let* malformed_timestamp_result =
    Typed_sql_caqti_lwt.fetch_one ~conn malformed_timestamp_collection
  in
  assert_codec_error
    "multiset element 1.1: expected timestamp, got 2024-01-02X03:04:05"
    malformed_timestamp_result;
  let* () =
    Connection.exec (direct "DELETE FROM events WHERE id = 6") () |> caqti_or_fail
  in
  let calendar_date = Date.of_ymd_exn ~year:2026 ~month:9 ~day:12 in
  let date_insert =
    Insert.(
      into Calendar_day.table
      |> set Calendar_day.id_column 1L
      |> set Calendar_day.date_column calendar_date
      |> returning (fun day -> Projection.expr (Calendar_day.date day)))
  in
  let* decoded_date =
    Typed_sql_caqti_lwt.fetch_one ~conn date_insert >>= adapter_or_fail
  in
  if not (Date.equal calendar_date decoded_date) then
    failwith "date codec changed a bound value";
  let uuid = Uuid.of_string_exn "550e8400-e29b-41d4-a716-446655440000" in
  let uuid_insert =
    Insert.(
      into Resource.table
      |> set Resource.id_column 1L
      |> set Resource.external_id_column uuid
      |> returning (fun resource -> Projection.expr (Resource.external_id resource)))
  in
  let* decoded_uuid =
    Typed_sql_caqti_lwt.fetch_one ~conn uuid_insert >>= adapter_or_fail
  in
  if not (Uuid.equal uuid decoded_uuid) then
    failwith "UUID codec changed a bound value";
  let temporal_collection =
    Query.(
      from Event.table
      |> select_exactly_one (fun event ->
        Projection.multiset_agg
          ~order_by:[ Aggregate_order.asc (Event.id event) ]
          (Projection.expr (Event.occurred_at event))))
  in
  let* temporal_collection =
    Typed_sql_caqti_lwt.fetch_one ~conn temporal_collection >>= adapter_or_fail
  in
  (match temporal_collection with
   | first :: _ :: positive_offset :: lower_z :: [ negative_offset ]
     when Ptime.equal first timestamp
          && Ptime.equal positive_offset timestamp
          && Ptime.equal lower_z timestamp
          && Ptime.equal negative_offset timestamp -> ()
   | _ -> failwith "timestamp multiset codec changed values");
  let date_collection =
    Query.(
      from Calendar_day.table
      |> select_exactly_one (fun day ->
        Projection.multiset_agg (Projection.expr (Calendar_day.date day))))
  in
  let* dates = Typed_sql_caqti_lwt.fetch_one ~conn date_collection >>= adapter_or_fail in
  if not (List.equal Date.equal dates [ calendar_date ]) then
    failwith "date multiset codec changed values";
  let uuid_collection =
    Query.(
      from Resource.table
      |> select_exactly_one (fun resource ->
        Projection.multiset_agg (Projection.expr (Resource.external_id resource))))
  in
  let* uuids = Typed_sql_caqti_lwt.fetch_one ~conn uuid_collection >>= adapter_or_fail in
  if not (List.equal Uuid.equal uuids [ uuid ]) then
    failwith "UUID multiset codec changed values";
  Lwt.return_unit
;;

let upsert_test conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let table : unit Table.t = Table.v_exn "excluded" in
  let id = Column.v_exn table "id" Db_type.int64 in
  let key = Column.v_exn table "key" Db_type.text in
  let version = Column.v_exn table "version" Db_type.int64 in
  let role = Column.v_exn table "role" Person.role_type in
  let note = Column.nullable_v_exn table "note" Db_type.text in
  let target = Insert.Conflict_target.(column id |> add key) in
  let projection row =
    Projection.map3
      ~f:(fun version role note -> version, role, note)
      (Projection.expr (Expr.column row version))
      (Projection.expr (Expr.column row role))
      (Projection.expr (Expr.column row note))
  in
  let row id_value key_value version_value builder =
    Insert.(
      builder
      |> set id id_value
      |> set key key_value
      |> set version version_value
      |> set role `Guest
      |> set note None)
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE excluded (id INTEGER, key TEXT, version INTEGER, role TEXT, note TEXT, PRIMARY KEY (id, key))")
      ()
    |> caqti_or_fail
  in
  let fetch query = Typed_sql_caqti_lwt.fetch ~conn query >>= adapter_or_fail in
  let equal = equal_triple Int64.equal Person.equal_role (Option.equal String.equal) in
  let upsert builders =
    Insert.(
      rows table builders
      |> on_conflict target
      |> do_update (fun ~existing ~excluded ->
        Conflict_update.(
          empty
          |> set_expr version (Expr.column excluded version)
          |> set_expr role (Expr.column excluded role)
          |> set_opt note (Some None)
          |> set_expr_opt key None
          |> where (Expr.column excluded version >. Expr.column existing version)
          |> where (Expr.column excluded key <>$ "skip")))
      |> returning projection)
  in
  let* inserted = fetch (upsert [ row 1L "a" 1L; row 2L "b" 2L ]) in
  assert_equal ~equal [ 1L, `Guest, None; 2L, `Guest, None ] inserted;
  let* updated = fetch (upsert [ row 1L "a" 10L; row 2L "b" 1L; row 3L "skip" 1L ]) in
  assert_equal ~equal [ 10L, `Guest, None; 1L, `Guest, None ] updated;
  let* skipped = fetch (upsert [ row 3L "skip" 20L ]) in
  assert (List.is_empty skipped);
  let ignored =
    Insert.(
      rows table [ row 1L "a" 99L ]
      |> on_conflict target
      |> do_nothing
      |> returning projection)
  in
  let* ignored = fetch ignored in
  assert (List.is_empty ignored);
  let null_predicate =
    Insert.(
      rows table [ row 1L "a" 99L ]
      |> on_conflict target
      |> do_update (fun ~existing ~excluded:_ ->
        Conflict_update.(
          empty |> set version 100L |> where (Expr.column existing note =$ Some "never")))
      |> returning projection)
  in
  let* skipped = fetch null_predicate in
  assert (List.is_empty skipped);
  let correlated =
    Insert.(
      rows table [ row 1L "a" 11L ]
      |> on_conflict target
      |> do_update (fun ~existing ~excluded ->
        let exists =
          Query.(
            from table
            |> where (fun inner ->
              Expr.column inner key
              =. Expr.column existing key
              &&. (Expr.column inner version <. Expr.column excluded version))
            |> exists)
        in
        Conflict_update.(
          empty
          |> set_expr version (Expr.column excluded version)
          |> set_opt role (Some `Admin)
          |> set_expr_opt
               note
               (Some (Expr.constant (Db_type.option Db_type.text) (Some "changed")))
          |> where exists))
      |> returning projection)
  in
  let* updated = fetch correlated in
  assert_equal ~equal [ 11L, `Admin, Some "changed" ] updated;
  let snapshot =
    Query.(
      from table |> order_by (fun row -> Expr.column row id) `Asc |> select projection)
  in
  let* final = fetch snapshot in
  assert_equal
    ~equal
    [ 11L, `Admin, Some "changed"; 2L, `Guest, None; 1L, `Guest, None ]
    final;
  Connection.exec (direct "DROP TABLE excluded") () |> caqti_or_fail
;;

let dynamic_test conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let* () =
    Connection.exec (direct "CREATE TABLE dynamic_items (id INTEGER NOT NULL)") ()
    |> caqti_or_fail
  in
  let table : unit Table.t = Table.v_exn "dynamic_items" in
  let id = Column.v_exn table "id" Db_type.int in
  let insert =
    Statement.Dynamic.command ~dialect:Dialect.sqlite (fun value ->
      Insert.(into table |> set id value |> command))
  in
  let* _ = Adapter.run ~conn insert 1 >>= adapter_or_fail in
  let* _ = Adapter.run ~conn insert 2 >>= adapter_or_fail in
  let builds = ref 0 in
  let query (ids, suffix) =
    Int.incr builds;
    Query.(
      from table
      |> where (fun row -> Expr.in_ (Expr.column row id) ids)
      |> order_by (fun row -> Expr.column row id) `Asc
      |> select (fun row ->
        Projection.map
          (Projection.expr (Expr.column row id))
          ~f:(fun value -> Int.to_string value ^ suffix)))
  in
  let many = Statement.Dynamic.query_many ~dialect:Dialect.sqlite query in
  let one = Statement.Dynamic.expect_one ~dialect:Dialect.sqlite query in
  let optional = Statement.Dynamic.expect_optional ~dialect:Dialect.sqlite query in
  assert (Int.(!builds = 0));
  let* rows = Adapter.run ~conn many ([ 1; 2 ], "a") >>= adapter_or_fail in
  assert (List.equal String.equal rows [ "1a"; "2a" ]);
  assert (Int.(!builds = 1));
  let* rows = Adapter.run ~conn many ([ 2 ], "b") >>= adapter_or_fail in
  assert (List.equal String.equal rows [ "2b" ]);
  let* rows = Adapter.run ~conn many ([], "") >>= adapter_or_fail in
  assert (List.is_empty rows);
  let* row = Adapter.run ~conn one ([ 1 ], "c") >>= adapter_or_fail in
  assert (String.equal row "1c");
  let* row = Adapter.run ~conn optional ([ 2 ], "d") >>= adapter_or_fail in
  assert (Option.equal String.equal row (Some "2d"));
  let* row = Adapter.run ~conn optional ([], "") >>= adapter_or_fail in
  assert (Option.is_none row);
  let* missing = Adapter.run ~conn one ([], "") in
  assert (Result.is_error missing);
  let* too_many = Adapter.run ~conn optional ([ 1; 2 ], "") in
  assert (Result.is_error too_many);
  let* too_many = Adapter.run ~conn one ([ 1; 2 ], "") in
  assert (Result.is_error too_many);
  assert (Int.(!builds = 9));
  let invalid =
    Statement.Dynamic.query_many ~dialect:Dialect.sqlite (fun maximum_rows ->
      Query.(
        from table
        |> limit maximum_rows
        |> select (fun row -> Projection.expr (Expr.column row id))))
  in
  let* error = Adapter.run ~conn invalid (-1) in
  (match error with
   | Error (Adapter.Compile ({ dialect = Sqlite; error = Negative_limit -1 } as error)) ->
     assert (
       String.is_substring (Adapter.error_to_string (Compile error)) ~substring:"LIMIT")
   | _ -> failwith "dynamic compilation error did not reach adapter");
  let escaped = ref None in
  ignore
    Query.(
      from table
      |> select (fun row ->
        escaped := Some row;
        Projection.expr (Expr.column row id)));
  let invalid =
    Statement.Dynamic.query_many ~dialect:Dialect.sqlite (fun () ->
      Query.(
        from table
        |> select (fun _ -> Projection.expr (Expr.column (Option.value_exn !escaped) id))))
  in
  let* error = Adapter.run ~conn invalid () in
  (match error with
   | Error (Adapter.Compile { error = Foreign_source _; _ }) -> ()
   | _ -> failwith "foreign source did not reach adapter");
  let invalid =
    Statement.Dynamic.command ~dialect:Dialect.sqlite (fun value ->
      Insert.(into table |> set id value |> set id value |> command))
  in
  let* error = Adapter.run ~conn invalid 3 in
  (match error with
   | Error (Adapter.Compile { error = Duplicate_assignment column; _ }) ->
     assert (String.equal (Identifier.to_string column) "id")
   | _ -> failwith "command compilation error did not reach adapter");
  Connection.exec (direct "DROP TABLE dynamic_items") () |> caqti_or_fail
;;

module Average_fixture = struct
  type blog
  type post

  let blogs : blog Table.t = Table.v_exn "average_blogs"
  let posts : post Table.t = Table.v_exn "average_posts"
  let id = Column.v_exn blogs "id" Db_type.int
  let rating = Column.v_exn blogs "rating" Db_type.int
  let optional_rating = Column.nullable_v_exn blogs "optional_rating" Db_type.int
  let owner = Column.v_exn posts "owner" Db_type.int
  let value = Column.nullable_v_exn posts "value" Db_type.int

  let average target =
    Query.(
      from posts
      |> where (fun post -> Expr.column post owner =. Expr.column target id)
      |> select_scalar (fun post -> Expr.avg_int_nullable (Expr.column post value)))
  ;;

  let update_nullable =
    Update.(
      table blogs
      |> with_target ~f:(fun target update ->
        update
        |> set_expr
             optional_rating
             (Expr.cast_float_to_int_nullable
                (Expr.scalar_subquery_nullable (average target))))
      |> all_rows
      |> command)
  ;;

  let update_required =
    Update.(
      table blogs
      |> with_target ~f:(fun target update ->
        update
        |> set_nullable_expr
             rating
             (Expr.cast_float_to_int_nullable
                (Expr.scalar_subquery_nullable (average target))))
      |> all_rows
      |> command)
  ;;

  let rows =
    Query.(
      from blogs
      |> order_by (fun blog -> Expr.column blog id) `Asc
      |> select (fun blog ->
        Projection.both
          (Projection.expr (Expr.column blog rating))
          (Projection.expr (Expr.column blog optional_rating))))
  ;;
end

let test_average conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let exec sql = Connection.exec (direct sql) () |> caqti_or_fail in
  let* () =
    exec
      "CREATE TABLE average_blogs (id INTEGER PRIMARY KEY, rating INTEGER NOT NULL, optional_rating INTEGER)"
  in
  let* () = exec "CREATE TABLE average_posts (owner INTEGER NOT NULL, value INTEGER)" in
  let* () =
    exec "INSERT INTO average_blogs VALUES (1,99,99),(2,99,99),(3,99,99),(4,99,99)"
  in
  let* () =
    exec "INSERT INTO average_posts VALUES (1,2),(1,3),(1,NULL),(2,-2),(2,-3),(4,NULL)"
  in
  let run statement = Adapter.run ~conn statement () >>= adapter_or_fail in
  let* _ =
    run (Statement.command ~dialect:Dialect.sqlite Average_fixture.update_nullable)
  in
  let fetch () =
    run (Statement.query_many ~dialect:Dialect.sqlite Average_fixture.rows)
  in
  let* rows = fetch () in
  let equal =
    List.equal (fun (a, b) (c, d) -> Int.equal a c && Option.equal Int.equal b d)
  in
  assert (equal rows [ 99, Some 2; 99, Some (-2); 99, None; 99, None ]);
  let* () = exec "SAVEPOINT average_failure" in
  let* error =
    Adapter.run
      ~conn
      (Statement.command ~dialect:Dialect.sqlite Average_fixture.update_required)
      ()
  in
  (match error with
   | Error (Adapter.Constraint_violation { kind = Not_null; _ }) -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok _ -> failwith "NULL average did not violate NOT NULL");
  let* after_failure = fetch () in
  assert (equal rows after_failure);
  let* () = exec "ROLLBACK TO SAVEPOINT average_failure" in
  let* () = exec "RELEASE SAVEPOINT average_failure" in
  let* unchanged = fetch () in
  assert (equal rows unchanged);
  let average owner =
    Query.(
      from Average_fixture.posts
      |> where (fun post -> Expr.column post Average_fixture.owner =$ owner)
      |> select (fun post ->
        Projection.expr (Expr.avg_int_nullable (Expr.column post Average_fixture.value))))
  in
  let check owner expected =
    let* value = run (Statement.expect_one ~dialect:Dialect.sqlite (average owner)) in
    assert (Option.equal Float.equal value expected);
    Lwt.return_unit
  in
  let* () = check 1 (Some 2.5) in
  let* () = check 2 (Some (-2.5)) in
  let* () = check 3 None in
  let* () = check 4 None in
  let* () = exec "UPDATE average_blogs SET rating = id" in
  let self_update =
    Update.(
      table Average_fixture.blogs
      |> with_target ~f:(fun target update ->
        let scalar =
          Query.(
            from Average_fixture.blogs
            |> where (fun row ->
              Expr.column row Average_fixture.id =. Expr.column target Average_fixture.id)
            |> select_scalar (fun row ->
              Expr.avg_int (Expr.column row Average_fixture.rating)))
        in
        update
        |> set_nullable_expr
             Average_fixture.rating
             (Expr.cast_float_to_int_nullable (Expr.scalar_subquery_nullable scalar)))
      |> all_rows
      |> command)
  in
  let* _ = run (Statement.command ~dialect:Dialect.sqlite self_update) in
  let* self_rows = fetch () in
  assert (List.equal Int.equal (List.map self_rows ~f:fst) [ 1; 2; 3; 4 ]);
  let check_nullable expression equal expected =
    let* actual =
      run (Statement.query_one ~dialect:Dialect.sqlite (Query.select_one expression))
    in
    assert (equal actual expected);
    Lwt.return_unit
  in
  let* () =
    check_nullable
      (Expr.cast_int_to_int64_nullable (Expr.constant (Db_type.option Db_type.int) None))
      (Option.equal Int64.equal)
      None
  in
  let* () =
    check_nullable
      (Expr.cast_int64_to_float_nullable
         (Expr.constant (Db_type.option Db_type.int64) (Some 3L)))
      (Option.equal Float.equal)
      (Some 3.)
  in
  let* () =
    check_nullable
      (Expr.cast_float_to_int_nullable
         (Expr.constant (Db_type.option Db_type.float) None))
      (Option.equal Int.equal)
      None
  in
  let* () = exec "DROP TABLE average_posts" in
  exec "DROP TABLE average_blogs"
;;

let test_debug_sql_text conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let statement =
    Statement.query_one
      ~dialect:Dialect.sqlite
      (Query.select_one (Expr.constant Db_type.text "A\000B'\\C"))
  in
  let sql = Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement in
  let* bound = Adapter.run ~conn statement () >>= adapter_or_fail in
  let* literal = Connection.find (direct_string sql) () |> caqti_or_fail in
  if not (String.equal bound literal) then
    failwith "SQLite text literal differs from its bound parameter";
  Lwt.return_unit
;;

let test_debug_sql_min_int64 conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let statement =
    Statement.query_one
      ~dialect:Dialect.sqlite
      (Query.select_one (Expr.constant Db_type.int64 Int64.min_value))
  in
  let sql = Statement.debug_sql_exn ~dialect:Sqlite ~input:() statement in
  let* bound = Adapter.run ~conn statement () >>= adapter_or_fail in
  let* literal = Connection.find (direct_int64 sql) () |> caqti_or_fail in
  if not (Int64.equal bound literal) then
    failwith "SQLite minimum int64 literal differs from its bound parameter";
  Lwt.return_unit
;;

let main () =
  let* conn =
    Caqti_lwt_unix.connect (Uri.of_string "sqlite3::memory:") |> caqti_or_fail
  in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize
    (fun () ->
       let* () = test_average conn in
       let* () = dynamic_test conn in
       let* () = upsert_test conn in
       let* () = test_debug_sql_text conn in
       let* () = test_debug_sql_min_int64 conn in
       run conn)
    (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
