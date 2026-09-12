open! Base
open Typed_sql
open Infix
module T = Caqti.Template

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

let run conn =
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
         "CREATE TABLE schema_parents (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE)")
      ()
    |> caqti_or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE schema_children (id INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL, nickname TEXT DEFAULT 'unknown', display_name TEXT GENERATED ALWAYS AS (nickname || '!') VIRTUAL, FOREIGN KEY (parent_id) REFERENCES schema_parents (id), UNIQUE (parent_id, nickname))")
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
            [ Projection.expr (Expr.param Db_type.int 11)
            ; Projection.apply
                (Projection.return Int.succ)
                (Projection.expr (Expr.param Db_type.int 22))
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
  let* encode_failure = Typed_sql_caqti_lwt.execute ~conn codec_encode_failure in
  assert_codec_error "encode rejected by test codec" encode_failure;
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
  let* decode_failure = Typed_sql_caqti_lwt.fetch ~conn codec_decode_failure in
  assert_codec_error "decode rejected by test codec" decode_failure;
  let* decode_failure = Typed_sql_caqti_lwt.fetch_one ~conn codec_decode_failure in
  assert_codec_error "decode rejected by test codec" decode_failure;
  let* decode_failure = Typed_sql_caqti_lwt.fetch_opt ~conn codec_decode_failure in
  assert_codec_error "decode rejected by test codec" decode_failure;
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
        Expr.in_exprs (Person.id person) [ Expr.param Db_type.int64 1L ]
        &&. Expr.not_in_exprs (Person.id person) [ Expr.param Db_type.int64 2L ]
        &&. Expr.between_exprs
              (Person.id person)
              ~lower:(Expr.param Db_type.int64 1L)
              ~upper:(Expr.param Db_type.int64 3L))
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
                     (Expr.param Db_type.text "!"))))
          (Projection.expr
             ((Person.id person +. Expr.param Db_type.int64 5L)
              *. Expr.param Db_type.int64 2L))
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
         (equal_pair String.equal String.equal)
         people_with_departments
         [ "Mathematics", "Mathematics" ])
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
  let* duplicate = Typed_sql_caqti_lwt.execute ~conn duplicate in
  (match duplicate with
   | Error (Typed_sql_caqti_lwt.Constraint_violation { kind = Other; _ }) -> ()
   | Error error ->
     failwith
       ("expected SQLite integrity error, got "
        ^ Typed_sql_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "duplicate primary key unexpectedly succeeded");
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
  let* schema = Typed_sql_caqti_lwt.Schema.introspect ~conn >>= adapter_or_fail in
  let find_table name =
    List.find_exn (Schema_ir.tables schema) ~f:(fun table ->
      String.equal (Identifier.to_string (Schema_ir.table_name table)) name)
  in
  let child = find_table "schema_children" in
  if Option.is_some (Schema_ir.table_schema child) then
    failwith "SQLite introspection returned a schema qualifier";
  let find_column name =
    List.find_exn (Schema_ir.columns child) ~f:(fun column ->
      String.equal (Identifier.to_string (Schema_ir.column_name column)) name)
  in
  let id = find_column "id" in
  let nickname = find_column "nickname" in
  let display_name = find_column "display_name" in
  if
    not
      ((match Schema_ir.column_db_type id with
        | Schema_ir.Int64 -> true
        | _ -> false)
       && Option.equal Int.equal (Schema_ir.column_primary_key_position id) (Some 1)
       && Schema_ir.column_nullable nickname
       && Option.equal String.equal (Schema_ir.column_default nickname) (Some "'unknown'")
       && Schema_ir.column_generated display_name)
  then
    failwith "SQLite column introspection lost metadata";
  (match Schema_ir.foreign_keys child with
   | [ foreign_key ] ->
     let names identifiers = List.map identifiers ~f:Identifier.to_string in
     if
       not
         (List.equal
            String.equal
            (names (Schema_ir.foreign_key_columns foreign_key))
            [ "parent_id" ]
          && Option.is_none (Schema_ir.foreign_key_referenced_schema foreign_key)
          && String.equal
               (Identifier.to_string (Schema_ir.foreign_key_referenced_table foreign_key))
               "schema_parents"
          && List.equal
               String.equal
               (names (Schema_ir.foreign_key_referenced_columns foreign_key))
               [ "id" ])
     then
       failwith "SQLite foreign-key introspection returned the wrong columns"
   | _ -> failwith "SQLite foreign-key introspection returned the wrong key count");
  (match Schema_ir.unique_constraints child with
   | [ constraint_ ] ->
     if
       not
         (List.equal
            String.equal
            (List.map
               (Schema_ir.unique_constraint_columns constraint_)
               ~f:Identifier.to_string)
            [ "parent_id"; "nickname" ])
     then
       failwith "SQLite unique introspection returned the wrong columns"
   | _ -> failwith "SQLite unique introspection returned the wrong constraint count");
  (match Typed_sql.Schema_codegen.generate schema with
   | Ok source when not (String.is_empty source) -> ()
   | Ok _ -> failwith "schema generator returned empty source"
   | Error error -> failwith (Schema_codegen.error_to_string error));
  Lwt.return_unit
;;

let main () =
  let* conn =
    Caqti_lwt_unix.connect (Uri.of_string "sqlite3::memory:") |> caqti_or_fail
  in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize (fun () -> run conn) (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
