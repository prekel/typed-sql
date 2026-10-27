open! Base
open Typed_sql_schema
module Table_options = Typed_sql_schema_backend.Schema_dump_options

type options =
  { schema_path : string
  ; rules_path : string option
  ; included_tables : (Identifier.t * Identifier.t) list
  ; excluded_tables : (Identifier.t * Identifier.t) list
  }

type argument_error =
  | Help
  | Usage

let usage =
  "Usage: typed-sql-codegen [--include-table SCHEMA.TABLE]... "
  ^ "[--exclude-table SCHEMA.TABLE]... " ^ "[--type-rules RULES.json] SCHEMA.json|-"
;;

let read path =
  try
    Ok
      (if String.equal path "-" then
         Stdlib.In_channel.input_all Stdlib.stdin
       else
         Stdlib.In_channel.with_open_bin path Stdlib.In_channel.input_all)
  with
  | Sys_error message -> Error message
;;

let parse_args arguments =
  let rec loop schema_path rules_path included_tables excluded_tables = function
    | [] ->
      (match schema_path with
       | None -> Error Usage
       | Some schema_path ->
         Ok
           { schema_path
           ; rules_path
           ; included_tables = List.rev included_tables
           ; excluded_tables = List.rev excluded_tables
           })
    | [ "--help" ] | [ "-h" ] -> Error Help
    | "--include-table" :: table_name :: rest ->
      (match Table_options.parse_qualified_table table_name with
       | Error _ -> Error Usage
       | Ok table ->
         loop schema_path rules_path (table :: included_tables) excluded_tables rest)
    | "--exclude-table" :: table_name :: rest ->
      (match Table_options.parse_qualified_table table_name with
       | Error _ -> Error Usage
       | Ok table ->
         loop schema_path rules_path included_tables (table :: excluded_tables) rest)
    | ("--include-table" | "--exclude-table") :: [] -> Error Usage
    | "--type-rules" :: path :: rest when Option.is_none rules_path ->
      loop schema_path (Some path) included_tables excluded_tables rest
    | "--type-rules" :: _ -> Error Usage
    | path :: rest when String.equal path "-" || not (String.is_prefix path ~prefix:"-")
      ->
      (match schema_path with
       | None -> loop (Some path) rules_path included_tables excluded_tables rest
       | Some _ -> Error Usage)
    | _ -> Error Usage
  in
  loop None None [] [] arguments
;;

let run { schema_path; rules_path; included_tables; excluded_tables } =
  let open Result.Let_syntax in
  let%bind source = read schema_path in
  let%bind rules =
    match rules_path with
    | None -> Ok []
    | Some rules_path ->
      let%bind source = read rules_path in
      Schema_codegen.rules_of_string source
  in
  let%bind schema =
    Schema_snapshot.of_string source
    |> Result.map_error ~f:Schema_snapshot.error_to_string
  in
  let%bind schema =
    Table_options.filter_tables ~included_tables ~excluded_tables schema
  in
  Schema_codegen.generate ~rules schema
  |> Result.map_error ~f:Schema_codegen.error_to_string
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
  | Ok options ->
    (match run options with
     | Ok source -> Stdlib.print_string source
     | Error message ->
       Stdlib.prerr_endline ("typed-sql-codegen: " ^ message);
       Stdlib.exit 1)
;;
