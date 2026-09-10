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
  let nickname_column = Column.nullable_v_exn table "nickname" Db_type.text
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

module Department = struct
  type row

  let table : row Table.t = Table.v_exn "departments"
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let person_id reference = Expr.column reference person_id_column
  let nullable_name reference = Expr.nullable_column reference name_column
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
         "CREATE TABLE departments (person_id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
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
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person ->
      Condition.all
        [ Expr.gt_value Db_type.Ordering.int64 (Person.id person) 0L
        ; Expr.eq_value (Person.role person) `Admin
        ; Expr.like_value (Person.name person) "%d%"
        ])
    |> Query.order_by (fun person -> Person.id person) `Asc
  in
  let* rows =
    Typed_sql_caqti_lwt.fetch ~conn (Query.to_result query) >>= adapter_or_fail
  in
  assert_equal [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None } ] rows;
  let* row =
    Typed_sql_caqti_lwt.fetch_one ~conn (Query.to_result query) >>= adapter_or_fail
  in
  if not (Int64.equal row.id 1L) then
    failwith "fetch_one returned the wrong row";
  let missing =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person -> Expr.eq_value (Person.name person) "missing")
  in
  let* missing =
    Typed_sql_caqti_lwt.fetch_opt ~conn (Query.to_result missing) >>= adapter_or_fail
  in
  if Option.is_some missing then
    failwith "fetch_opt unexpectedly returned a row";
  let injection = "'; DROP TABLE people; --" in
  let injected =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person -> Expr.eq_value (Person.name person) injection)
  in
  let* rows =
    Typed_sql_caqti_lwt.fetch ~conn (Query.to_result injected) >>= adapter_or_fail
  in
  assert_equal [] rows;
  let all =
    Query.from Person.table ~select:Person.projection
    |> Query.where_opt None ~f:(fun person name ->
      Expr.eq_value (Person.name person) name)
    |> Query.order_by (fun person -> Person.id person) `Asc
  in
  let* rows = Typed_sql_caqti_lwt.fetch ~conn (Query.to_result all) >>= adapter_or_fail in
  assert_equal
    [ { Person.id = 1L; name = "Ada"; role = `Admin; nickname = None }
    ; { Person.id = 2L; name = "Grace"; role = `Guest; nickname = Some "Amazing Grace" }
    ; { Person.id = 3L; name = "Linus"; role = `Admin; nickname = Some "Lin" }
    ]
    rows;
  let departments =
    Query.from Person.table ~select:(fun person -> Projection.expr (Person.name person))
    |> Query.left_join Department.table ~on:(fun person department ->
      Expr.eq (Person.id person) (Department.person_id department))
    |> Query.select (fun (person, department) ->
      Projection.map2
        (fun person_name department_name -> person_name, department_name)
        (Projection.expr (Person.name person))
        (Projection.expr (Department.nullable_name department)))
    |> Query.order_by (fun (person, _) -> Person.id person) `Asc
    |> Query.to_result
  in
  let* departments = Typed_sql_caqti_lwt.fetch ~conn departments >>= adapter_or_fail in
  assert_equal [ "Ada", Some "Mathematics"; "Grace", None; "Linus", None ] departments;
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
    |> Update.where (fun person -> Expr.eq_value (Person.id person) 4L)
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
    |> Delete.where (fun person -> Expr.eq_value (Person.id person) 4L)
    |> Delete.command
  in
  let* _ = Typed_sql_caqti_lwt.execute ~conn delete >>= adapter_or_fail in
  let deleted =
    Query.from Person.table ~select:Person.projection
    |> Query.where (fun person -> Expr.eq_value (Person.id person) 4L)
    |> Query.to_result
  in
  let* deleted = Typed_sql_caqti_lwt.fetch_opt ~conn deleted >>= adapter_or_fail in
  if Option.is_some deleted then
    failwith "DELETE did not remove the row";
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
