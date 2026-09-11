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
  let nullable_name reference = Expr.nullable_column reference name_column
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

let assert_equal expected actual =
  if not (Poly.equal expected actual) then
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
  assert_equal [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None } ] rows;
  let* row = Typed_sql_caqti_lwt.fetch_one ~conn query >>= adapter_or_fail in
  if not (Int64.equal row.id 1L) then
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
  assert_equal [] rows;
  let all =
    Query.(
      from Person.table
      |> where_opt None ~f:(fun person name -> Person.name person =$ name)
      |> order_by (fun person -> Person.id person) `Asc
      |> select Person.projection)
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn all >>= adapter_or_fail in
  assert_equal
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
  assert_equal [ "Ada", Some "Mathematics"; "Grace", None; "Linus", None ] departments;
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
    Insert.into Codec_value.table
    |> Insert.set Codec_value.boolean_column codec_value.boolean
    |> Insert.set Codec_value.integer_column codec_value.integer
    |> Insert.set Codec_value.integer_64_column codec_value.integer_64
    |> Insert.set Codec_value.floating_column codec_value.floating
    |> Insert.set Codec_value.text_column codec_value.text
    |> Insert.set Codec_value.bytes_column codec_value.bytes
    |> Insert.set Codec_value.nullable_text_column codec_value.nullable_text
    |> Insert.returning Codec_value.projection
  in
  let* decoded_codec =
    Typed_sql_caqti_lwt.fetch_one ~conn codec_insert >>= adapter_or_fail
  in
  if not (Poly.equal codec_value decoded_codec) then
    failwith "database type round-trip changed a value";
  let inserted =
    Insert.into Person.table
    |> Insert.set Person.id_column 4L
    |> Insert.set Person.name_column "Edsger"
    |> Insert.set Person.role_column `Guest
    |> Insert.set Person.nickname_column None
    |> Insert.returning Person.projection
  in
  let* inserted = Typed_sql_caqti_lwt.fetch_one ~conn inserted >>= adapter_or_fail in
  if not (Int64.equal inserted.id 4L) then
    failwith "INSERT RETURNING returned the wrong row";
  let update =
    Update.table Person.table
    |> Update.set Person.name_column "Dijkstra"
    |> Update.where (fun person -> Person.id person =$ 4L)
    |> Update.command
  in
  let* affected = Typed_sql_caqti_lwt.execute ~conn update >>= adapter_or_fail in
  (match affected with
   | Affected_rows.Known 1 -> ()
   | Affected_rows.Known count ->
     failwith ("UPDATE affected " ^ Int.to_string count ^ " rows")
   | Affected_rows.Unknown -> ());
  let delete =
    Delete.from Person.table
    |> Delete.where (fun person -> Person.id person =$ 4L)
    |> Delete.command
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
    Insert.into Mapped_failure.table
    |> Insert.set Mapped_failure.encode_column "bad"
    |> Insert.set Mapped_failure.decode_column "ok"
    |> Insert.command
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
