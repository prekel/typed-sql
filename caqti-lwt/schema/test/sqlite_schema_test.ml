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

let caqti_or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

let adapter_or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Typed_sql_schema_caqti_lwt.error_to_string error)
;;

let test_schema conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let definitions =
    [ "CREATE TABLE resources (id INTEGER PRIMARY KEY, external_id UUID NOT NULL)"
    ; "CREATE TABLE calendar_days (id INTEGER PRIMARY KEY, calendar_date DATE NOT NULL)"
    ; "CREATE TABLE schema_parents (id INTEGER PRIMARY KEY, code TEXT NOT NULL UNIQUE)"
    ; "CREATE TABLE schema_children (id INTEGER PRIMARY KEY, parent_id INTEGER NOT NULL, nickname TEXT DEFAULT 'unknown', display_name TEXT GENERATED ALWAYS AS (nickname || '!') VIRTUAL, FOREIGN KEY (parent_id) REFERENCES schema_parents (id), UNIQUE (parent_id, nickname))"
    ; "CREATE TABLE schema_implicit_parent (id INTEGER PRIMARY KEY)"
    ; "CREATE TABLE schema_implicit_child (parent_id INTEGER REFERENCES schema_implicit_parent)"
    ; "CREATE TABLE schema_nullable_pk (id INT PRIMARY KEY)"
    ]
  in
  let* () =
    Lwt_list.iter_s
      (fun sql -> Connection.exec (direct sql) () |> caqti_or_fail)
      definitions
  in
  let* schema = Typed_sql_schema_caqti_lwt.introspect ~conn >>= adapter_or_fail in
  let find_table name =
    List.find_exn (Schema_ir.tables schema) ~f:(fun table ->
      String.equal (Identifier.to_string (Schema_ir.table_name table)) name)
  in
  let child = find_table "schema_children" in
  let calendar_days = find_table "calendar_days" in
  let rowid_primary_key = find_table "schema_implicit_parent" in
  let nullable_primary_key = find_table "schema_nullable_pk" in
  (match Schema_ir.columns calendar_days with
   | [ _; calendar_date ] ->
     (match Schema_ir.column_db_type calendar_date with
      | Date -> ()
      | _ -> failwith "SQLite DATE introspection returned the wrong type")
   | _ -> failwith "SQLite DATE introspection returned the wrong columns");
  let resources = find_table "resources" in
  (match Schema_ir.columns resources with
   | [ _; external_id ] ->
     (match Schema_ir.column_db_type external_id with
      | Uuid -> ()
      | _ -> failwith "SQLite UUID introspection returned the wrong type")
   | _ -> failwith "SQLite UUID introspection returned the wrong columns");
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
       && (not (Schema_ir.column_nullable id))
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
  let implicit_child = find_table "schema_implicit_child" in
  (match Schema_ir.foreign_keys implicit_child with
   | [ foreign_key ] ->
     if
       not
         (List.equal
            String.equal
            (List.map
               (Schema_ir.foreign_key_referenced_columns foreign_key)
               ~f:Identifier.to_string)
            [ "id" ])
     then
       failwith "SQLite implicit foreign key did not resolve the parent primary key"
   | _ -> failwith "SQLite implicit foreign key was not introspected");
  (match Schema_ir.columns rowid_primary_key, Schema_ir.columns nullable_primary_key with
   | [ id ], [ nullable_id ] ->
     if Schema_ir.column_nullable id || not (Schema_ir.column_nullable nullable_id) then
       failwith "SQLite primary-key nullability was inferred incorrectly"
   | _ -> failwith "SQLite primary-key test tables returned unexpected columns");
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
  (match Typed_sql_schema.Schema_codegen.generate schema with
   | Ok source when not (String.is_empty source) -> ()
   | Ok _ -> failwith "schema generator returned empty source"
   | Error error -> failwith (Schema_codegen.error_to_string error));
  let* () =
    Connection.exec
      (direct
         "CREATE TABLE schema_broken_child (parent_id INTEGER REFERENCES schema_missing_parent)")
      ()
    |> caqti_or_fail
  in
  let* broken_schema = Typed_sql_schema_caqti_lwt.introspect ~conn in
  (match broken_schema with
   | Error (Typed_sql_schema_caqti_lwt.Schema message)
     when String.is_substring message ~substring:"schema_missing_parent" -> ()
   | Error error -> failwith (Typed_sql_schema_caqti_lwt.error_to_string error)
   | Ok _ -> failwith "schema with an unresolved implicit foreign key was accepted");
  Lwt.return_unit
;;

let main () =
  let* conn =
    Caqti_lwt_unix.connect (Uri.of_string "sqlite3::memory:") |> caqti_or_fail
  in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize (fun () -> test_schema conn) (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
