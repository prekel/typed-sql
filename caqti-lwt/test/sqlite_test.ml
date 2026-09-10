open! Base
open Typed_sql
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
  let nickname_column = Column.v_exn table "nickname" (Db_type.option Db_type.text)
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column
  let role reference = Expr.column reference role_column
  let nickname reference = Expr.column reference nickname_column

  let projection reference =
    let identity ((id, name), (role, nickname)) = { id; name; role; nickname } in
    Projection.map
      identity
      (Projection.both
         (Projection.both
            (Projection.expr (id reference))
            (Projection.expr (name reference)))
         (Projection.both
            (Projection.expr (role reference))
            (Projection.expr (nickname reference))))
  ;;
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
         "INSERT INTO people (id, name, role, nickname) VALUES (1, 'Ada', 'admin', NULL), (2, 'Grace', 'guest', 'Amazing Grace'), (3, 'Linus', 'admin', 'Lin')")
      ()
    |> caqti_or_fail
  in
  let query =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person ->
      Condition.all
        [ Expr.gt_value Db_type.Ordering.int64 (Person.id person) 0L
        ; Expr.eq_value (Person.role person) `Admin
        ; Expr.like_value (Person.name person) "%d%"
        ])
    |> Query.order_by (fun person -> Person.id person) `Asc
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn query >>= adapter_or_fail in
  assert_equal [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None } ] rows;
  let* row = Typed_sql_caqti_lwt.fetch_one ~conn query >>= adapter_or_fail in
  if not (Int64.equal row.id 1L) then
    failwith "fetch_one returned the wrong row";
  let missing =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person -> Expr.eq_value (Person.name person) "missing")
  in
  let* missing = Typed_sql_caqti_lwt.fetch_opt ~conn missing >>= adapter_or_fail in
  if Option.is_some missing then
    failwith "fetch_opt unexpectedly returned a row";
  let injection = "'; DROP TABLE people; --" in
  let injected =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person -> Expr.eq_value (Person.name person) injection)
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn injected >>= adapter_or_fail in
  assert_equal [] rows;
  let all =
    Query.from Person.table ~select:Person.projection
    |> Query.where_opt None ~f:(fun person name ->
      Expr.eq_value (Person.name person) name)
    |> Query.order_by (fun person -> Person.id person) `Asc
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn all >>= adapter_or_fail in
  assert_equal
    [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None }
    ; { Person.id = 2L; name = "Grace"; role = `Guest; nickname = Some "Amazing Grace" }
    ; { Person.id = 3L; name = "Linus"; role = `Admin; nickname = Some "Lin" }
    ]
    rows;
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
