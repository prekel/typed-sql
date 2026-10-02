open! Base
open Typed_sql_schema
open Typed_sql_schema_backend.Schema_dump_options

let usage =
  "Usage: typed-sql-schema-dump [--exclude-table SCHEMA.TABLE]... [POSTGRESQL_URI]"
;;

let dump uri excluded_tables =
  let open Lwt.Syntax in
  let* connection = Caqti_lwt_unix.connect (Uri.of_string uri) in
  match connection with
  | Error error -> Lwt.return (Error (Caqti.Error.show error))
  | Ok conn ->
    let* schema = Typed_sql_schema_caqti_lwt.introspect ~conn in
    Lwt.return
      (match schema with
       | Error error -> Error (Typed_sql_schema_caqti_lwt.error_to_string error)
       | Ok schema ->
         Result.map (exclude_tables excluded_tables schema) ~f:Schema_snapshot.to_string)
;;

let () =
  let arguments =
    Stdlib.Array.sub Stdlib.Sys.argv 1 (Stdlib.Array.length Stdlib.Sys.argv - 1)
    |> Stdlib.Array.to_list
  in
  match parse_args arguments with
  | Error Help -> Stdlib.print_endline usage
  | Error Usage ->
    Stdlib.prerr_endline usage;
    Stdlib.exit 2
  | Ok { uri; excluded_tables } ->
    let uri = Option.value uri ~default:"postgresql://" in
    (match Lwt_main.run (dump uri excluded_tables) with
     | Ok snapshot -> Stdlib.print_string snapshot
     | Error message ->
       Stdlib.prerr_endline ("typed-sql-schema-dump: " ^ message);
       Stdlib.exit 1)
;;
