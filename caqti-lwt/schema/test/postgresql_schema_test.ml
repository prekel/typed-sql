open! Base
open Typed_sql_schema
module T = Caqti.Template

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

let schema_or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Typed_sql_schema_caqti_lwt.error_to_string error)
;;

let test_constraints conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let* () =
    Connection.exec (direct "CREATE TABLE postgres_items (id BIGINT PRIMARY KEY)") ()
    |> or_fail
  in
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE postgres_constraints (id BIGINT PRIMARY KEY, parent_id BIGINT REFERENCES postgres_items(id), value BIGINT CHECK (value > 0), note TEXT NOT NULL)")
      ()
    |> or_fail
  in
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
  let* schema = Typed_sql_schema_caqti_lwt.introspect ~conn >>= schema_or_fail in
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

let test_rich_types conn =
  let* schema = Typed_sql_schema_caqti_lwt.introspect ~conn >>= schema_or_fail in
  let table =
    List.find_exn (Schema_ir.tables schema) ~f:(fun table ->
      String.equal (Identifier.to_string (Schema_ir.table_name table)) "advanced")
  in
  let find name =
    List.find_exn (Schema_ir.columns table) ~f:(fun column ->
      String.equal (Identifier.to_string (Schema_ir.column_name column)) name)
    |> Schema_ir.column_db_type
  in
  (match find "float_value", find "duration", find "payload_binary", find "numbers" with
   | Timestamp_without_timezone, Interval, Jsonb, Array Int -> ()
   | _ -> failwith "PostgreSQL introspection lost structured built-in types");
  (match find "mood", find "host" with
   | Enum { labels = [ "happy"; "sad" ]; _ }, Domain { base = Named _; _ } -> ()
   | _ -> failwith "PostgreSQL introspection lost enum or domain structure");
  (match find "inet_value" with
   | Named { schema; name }
     when String.equal (Identifier.to_string schema) "pg_catalog"
          && String.equal (Identifier.to_string name) "inet" -> ()
   | _ -> failwith "PostgreSQL introspection lost direct inet type");
  Lwt.return_unit
;;

let main () =
  let* conn = Caqti_lwt_unix.connect (Uri.of_string "postgresql://") |> or_fail in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize
    (fun () ->
       let* () = test_constraints conn in
       test_rich_types conn)
    (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
