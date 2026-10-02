open! Base
open Typed_sql_schema
open Typed_sql_schema_backend.Schema_dump_options
module Pgocaml = Typed_sql_pgocaml_lwt.Pgocaml

let usage =
  "Usage: typed-sql-pgocaml-schema-dump [--exclude-table SCHEMA.TABLE]... [POSTGRESQL_URI]"
;;

type connection_options =
  { host : string option
  ; port : int option
  ; user : string option
  ; password : string option
  ; database : string option
  ; unix_domain_socket_dir : string option
  }

let connection_options source =
  let uri = Uri.of_string source in
  let open Result.Let_syntax in
  let%bind () =
    match Uri.scheme uri with
    | Some ("postgresql" | "postgres") -> Ok ()
    | _ -> Error "expected a postgresql:// URI"
  in
  let query = Uri.query uri in
  let%bind () =
    match List.find query ~f:(fun (name, _) -> not (String.equal name "host")) with
    | None -> Ok ()
    | Some (name, _) -> Error ("unsupported URI parameter: " ^ name)
  in
  let%bind query_host =
    match List.Assoc.find query "host" ~equal:String.equal with
    | None -> Ok None
    | Some [ value ] -> Ok (Some value)
    | Some _ -> Error "URI parameter host must have one value"
  in
  let%bind () =
    match Uri.fragment uri with
    | None -> Ok ()
    | Some _ -> Error "URI fragment is unsupported"
  in
  let user, password =
    match Uri.userinfo uri with
    | None -> None, None
    | Some userinfo ->
      (match String.lsplit2 userinfo ~on:':' with
       | Some (user, password) ->
         Some (Uri.pct_decode user), Some (Uri.pct_decode password)
       | None -> Some (Uri.pct_decode userinfo), None)
  in
  let uri_host =
    match Uri.host uri with
    | Some "" | None -> None
    | host -> host
  in
  let host = Option.first_some query_host uri_host in
  let host, unix_domain_socket_dir =
    match host with
    | Some host when String.is_prefix host ~prefix:"/" -> None, Some host
    | host -> host, None
  in
  let database =
    match Uri.path uri with
    | "" | "/" -> None
    | path -> Some (Uri.pct_decode (String.drop_prefix path 1))
  in
  Ok { host; port = Uri.port uri; user; password; database; unix_domain_socket_dir }
;;

let dump uri excluded_tables =
  let open Lwt.Syntax in
  match connection_options uri with
  | Error message -> Lwt.return (Error message)
  | Ok { host; port; user; password; database; unix_domain_socket_dir } ->
    Lwt.catch
      (fun () ->
         let* conn =
           Pgocaml.connect
             ?host
             ?port
             ?user
             ?password
             ?database
             ?unix_domain_socket_dir
             ()
         in
         Lwt.finalize
           (fun () ->
              let* schema = Typed_sql_schema_pgocaml_lwt.introspect ~conn in
              Lwt.return
                (match schema with
                 | Error error ->
                   Error (Typed_sql_schema_pgocaml_lwt.error_to_string error)
                 | Ok schema ->
                   Result.map
                     (exclude_tables excluded_tables schema)
                     ~f:Schema_snapshot.to_string))
           (fun () -> Pgocaml.close conn))
      (fun exn -> Lwt.return (Error (Exn.to_string exn)))
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
       Stdlib.prerr_endline ("typed-sql-pgocaml-schema-dump: " ^ message);
       Stdlib.exit 1)
;;
