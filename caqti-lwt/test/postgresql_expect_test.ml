open! Base
open Typed_sql
open Infix
module T = Caqti.Template
module Adapter = Typed_sql_caqti_lwt

let ( let* ) = Lwt.bind

let or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

let adapter_or_fail promise =
  let* result = promise in
  match result with
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Adapter.error_to_string error)
;;

let direct sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit)
    (fun _ -> T.Query.parse sql)
;;

let raw_name sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.string)
    (fun _ -> T.Query.parse sql)
;;

let raw_id sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.int64)
    (fun _ -> T.Query.parse sql)
;;

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "typed_sql_debug_people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id person = Expr.column person id_column
  let name person = Expr.column person name_column
end

let find_name =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.column Person.id_column ~get:Fn.id in
    params.expect_one
      Query.(
        from Person.table
        |> where (fun person -> Person.id person =. id)
        |> select (fun person -> Projection.expr (Person.name person))))
;;

let find_id =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters name = params.column Person.name_column ~get:Fn.id in
    params.expect_one
      Query.(
        from Person.table
        |> where (fun person -> Person.name person =. name)
        |> select (fun person -> Projection.expr (Person.id person))))
;;

let with_seeded_connection f =
  let* conn = Caqti_lwt_unix.connect (Uri.of_string "postgresql://") |> or_fail in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize
    (fun () ->
       let* () =
         Connection.exec
           (direct
              "CREATE TEMP TABLE typed_sql_debug_people (id BIGINT PRIMARY KEY, name TEXT)")
           ()
         |> or_fail
       in
       let* () =
         Connection.exec
           (direct
              "INSERT INTO typed_sql_debug_people (id, name) VALUES (7, 'Ada'), (8, E'O''Reilly\\\\staff')")
           ()
         |> or_fail
       in
       f conn)
    (fun () -> Connection.disconnect ())
;;

let%expect_test "a PostgreSQL expect test can print the database result" =
  Lwt_main.run
    (with_seeded_connection (fun conn ->
       let* name = Adapter.run ~conn find_name 7L |> adapter_or_fail in
       Stdlib.print_endline name;
       Lwt.return_unit));
  [%expect {| Ada |}]
;;

let%test_unit "copyable SQL returns the same PostgreSQL row" =
  Lwt_main.run
    (with_seeded_connection (fun conn ->
       let module Connection = (val conn : Caqti_lwt.CONNECTION) in
       let sql = Statement.debug_sql_exn ~dialect:Postgresql ~input:7L find_name in
       let* typed = Adapter.run ~conn find_name 7L |> adapter_or_fail in
       let* copied = Connection.find (raw_name sql) () |> or_fail in
       if not (String.equal typed copied) then
         failwith "copyable SQL returned a different row";
       Lwt.return_unit))
;;

let%test_unit "copyable SQL preserves quotes and backslashes" =
  Lwt_main.run
    (with_seeded_connection (fun conn ->
       let module Connection = (val conn : Caqti_lwt.CONNECTION) in
       let input = "O'Reilly\\staff" in
       let sql = Statement.debug_sql_exn ~dialect:Postgresql ~input find_id in
       let* typed = Adapter.run ~conn find_id input |> adapter_or_fail in
       let* copied = Connection.find (raw_id sql) () |> or_fail in
       if not (Int64.equal typed copied) then
         failwith "copyable SQL changed the PostgreSQL text parameter";
       Lwt.return_unit))
;;
