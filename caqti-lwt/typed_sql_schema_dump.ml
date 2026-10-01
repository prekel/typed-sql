open! Base
open Typed_sql

let dump uri =
  let open Lwt.Syntax in
  let* connection = Caqti_lwt_unix.connect (Uri.of_string uri) in
  match connection with
  | Error error -> Lwt.return (Error (Caqti.Error.show error))
  | Ok conn ->
    let* schema = Typed_sql_caqti_lwt.Schema.introspect ~conn in
    Lwt.return
      (schema
       |> Result.map_error ~f:Typed_sql_caqti_lwt.error_to_string
       |> Result.map ~f:Schema_snapshot.to_string)
;;

let () =
  let uri =
    match Stdlib.Sys.argv with
    | [| _ |] -> "postgresql://"
    | [| _; uri |] -> uri
    | _ ->
      Stdlib.prerr_endline "Usage: typed-sql-schema-dump [POSTGRESQL_URI]";
      Stdlib.exit 2
  in
  match Lwt_main.run (dump uri) with
  | Ok snapshot -> Stdlib.print_string snapshot
  | Error message ->
    Stdlib.prerr_endline ("typed-sql-schema-dump: " ^ message);
    Stdlib.exit 1
;;
