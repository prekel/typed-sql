open! Base
module T = Caqti.Template

type error =
  | Unsupported_dialect of string
  | Schema of string
  | Caqti of Caqti.Error.t

let error_to_string = function
  | Unsupported_dialect dialect -> "unsupported Caqti dialect: " ^ dialect
  | Schema message -> "schema introspection failed: " ^ message
  | Caqti error -> Caqti.Error.show error
;;

let map_caqti_error = Result.map_error ~f:(fun error -> Caqti error)

module S = Typed_sql_schema_backend.Schema_introspection

type raw_column = S.raw_column
type raw_foreign_key = S.raw_foreign_key
type raw_unique = S.raw_unique
type raw_type = S.raw_type

let column_row_type : raw_column T.Row_type.t =
  T.Row_type.t4
    (T.Row_type.option T.Row_type.string)
    T.Row_type.string
    T.Row_type.string
    (T.Row_type.t4
       T.Row_type.string
       T.Row_type.bool
       (T.Row_type.option T.Row_type.string)
       (T.Row_type.t2 T.Row_type.bool (T.Row_type.option T.Row_type.int)))
;;

let foreign_key_row_type : raw_foreign_key T.Row_type.t =
  T.Row_type.t4
    (T.Row_type.option T.Row_type.string)
    T.Row_type.string
    (T.Row_type.option T.Row_type.string)
    (T.Row_type.t4
       T.Row_type.int
       T.Row_type.string
       (T.Row_type.option T.Row_type.string)
       (T.Row_type.t2 T.Row_type.string (T.Row_type.option T.Row_type.string)))
;;

let unique_row_type : raw_unique T.Row_type.t =
  T.Row_type.t4
    (T.Row_type.option T.Row_type.string)
    T.Row_type.string
    (T.Row_type.option T.Row_type.string)
    (T.Row_type.t2 T.Row_type.int T.Row_type.string)
;;

let type_row_type : raw_type T.Row_type.t =
  T.Row_type.t4
    T.Row_type.int
    T.Row_type.string
    T.Row_type.string
    (T.Row_type.t4 T.Row_type.string T.Row_type.int T.Row_type.int T.Row_type.string)
;;

let request row_type sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->* row_type)
    (fun _ -> T.Query.parse sql)
;;

let sqlite_columns =
  {|
SELECT NULL,
     m.name,
     x.name,
     x.type,
     x."notnull" = 0
       AND NOT
         (x.pk = 1
          AND upper(x.type) = 'INTEGER'
          AND (SELECT COUNT(*) FROM pragma_index_list(m.name) WHERE origin = 'pk') = 0),
     x.dflt_value,
     x.hidden IN (2, 3),
     CASE WHEN x.pk = 0 THEN NULL ELSE x.pk END
FROM sqlite_schema AS m
JOIN pragma_table_xinfo(m.name) AS x
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, x.cid|}
;;

let sqlite_foreign_keys =
  {|
SELECT NULL,
     m.name,
     CAST(f.id AS TEXT),
     f.seq,
     f."from",
     NULL,
     f."table",
     f."to"
FROM sqlite_schema AS m
JOIN pragma_foreign_key_list(m.name) AS f
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, f.id, f.seq|}
;;

let sqlite_uniques =
  {|
SELECT NULL,
     m.name,
     il.name,
     ii.seqno,
     ii.name
FROM sqlite_schema AS m
JOIN pragma_index_list(m.name) AS il
JOIN pragma_index_info(il.name) AS ii
WHERE m.type = 'table'
AND m.name NOT LIKE 'sqlite_%'
AND il."unique" = 1
AND il.origin <> 'pk'
ORDER BY m.name, il.name, ii.seqno|}
;;

let introspect_with ~conn ~columns_sql ~foreign_keys_sql ~uniques_sql ~db_type =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let open Lwt.Syntax in
  let* columns = Connection.collect_list (request column_row_type columns_sql) () in
  match map_caqti_error columns with
  | Error error -> Lwt.return (Error error)
  | Ok columns ->
    let* foreign_keys =
      Connection.collect_list (request foreign_key_row_type foreign_keys_sql) ()
    in
    (match map_caqti_error foreign_keys with
     | Error error -> Lwt.return (Error error)
     | Ok foreign_keys ->
       let* uniques = Connection.collect_list (request unique_row_type uniques_sql) () in
       Lwt.return
         (let open Result.Let_syntax in
          let%bind uniques = map_caqti_error uniques in
          S.make_schema ~db_type columns foreign_keys uniques
          |> Result.map_error ~f:(function S.Schema message -> Schema message)))
;;

let introspect ~conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match Connection.dialect with
  | T.Dialect.Sqlite _ ->
    introspect_with
      ~conn
      ~columns_sql:sqlite_columns
      ~foreign_keys_sql:sqlite_foreign_keys
      ~uniques_sql:sqlite_uniques
      ~db_type:S.sqlite_db_type
  | T.Dialect.Pgsql _ ->
    let open Lwt.Syntax in
    let* types = Connection.collect_list (request type_row_type S.postgresql_types) () in
    (match map_caqti_error types with
     | Error error -> Lwt.return (Error error)
     | Ok types ->
       introspect_with
         ~conn
         ~columns_sql:S.postgresql_columns
         ~foreign_keys_sql:S.postgresql_foreign_keys
         ~uniques_sql:S.postgresql_uniques
         ~db_type:(S.postgresql_type_mapper types))
  | T.Dialect.Mysql _ -> Lwt.return (Error (Unsupported_dialect "mysql"))
  | T.Dialect.Unknown _ -> Lwt.return (Error (Unsupported_dialect "unknown"))
  | _ -> Lwt.return (Error (Unsupported_dialect "unregistered"))
;;
