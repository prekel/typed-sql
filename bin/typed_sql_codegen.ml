open! Base
open Typed_sql_schema

type options =
  { schema_path : string
  ; rules_path : string option
  ; excluded_tables : (Identifier.t * Identifier.t) list
  }

type argument_error =
  | Help
  | Usage

let usage =
  "Usage: typed-sql-codegen [--exclude-table SCHEMA.TABLE]... "
  ^ "[--type-rules RULES.json] SCHEMA.json|-"
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

let parse_qualified_table source =
  let length = String.length source in
  let parse_identifier start =
    if Int.(start >= length) then
      Error "missing identifier"
    else if Char.equal source.[start] '"' then (
      let buffer = Stdlib.Buffer.create 16 in
      let rec quoted index =
        if Int.(index >= length) then
          Error "unterminated quoted identifier"
        else if Char.equal source.[index] '"' then
          if Int.(index + 1 < length) && Char.equal source.[index + 1] '"' then (
            Stdlib.Buffer.add_char buffer '"';
            quoted (index + 2))
          else
            Ok (Stdlib.Buffer.contents buffer, index + 1)
        else (
          Stdlib.Buffer.add_char buffer source.[index];
          quoted (index + 1))
      in
      quoted (start + 1))
    else (
      let rec unquoted index =
        if Int.(index >= length) || Char.equal source.[index] '.' then
          Ok (String.sub source ~pos:start ~len:(index - start), index)
        else if Char.equal source.[index] '"' then
          Error "a quote must begin an identifier"
        else
          unquoted (index + 1)
      in
      unquoted start)
  in
  let invalid_format () = Error "expected SCHEMA.TABLE" in
  match parse_identifier 0 with
  | Error _ -> invalid_format ()
  | Ok (schema, separator) ->
    if Int.(separator >= length) || not (Char.equal source.[separator] '.') then
      invalid_format ()
    else (
      match
        parse_identifier (separator + 1)
      with
      | Error _ -> invalid_format ()
      | Ok (table, end_index) ->
        if Int.(end_index <> length) then
          invalid_format ()
        else (
          match
            Identifier.of_string schema, Identifier.of_string table
          with
          | Ok schema, Ok table -> Ok (schema, table)
          | Error _, _ | _, Error _ -> invalid_format ()))
;;

let parse_args arguments =
  let rec loop schema_path rules_path excluded_tables = function
    | [] ->
      (match schema_path with
       | None -> Error Usage
       | Some schema_path ->
         Ok { schema_path; rules_path; excluded_tables = List.rev excluded_tables })
    | [ "--help" ] | [ "-h" ] -> Error Help
    | "--exclude-table" :: table_name :: rest ->
      (match parse_qualified_table table_name with
       | Error _ -> Error Usage
       | Ok table -> loop schema_path rules_path (table :: excluded_tables) rest)
    | "--exclude-table" :: [] -> Error Usage
    | "--type-rules" :: path :: rest when Option.is_none rules_path ->
      loop schema_path (Some path) excluded_tables rest
    | "--type-rules" :: _ -> Error Usage
    | path :: rest when String.equal path "-" || not (String.is_prefix path ~prefix:"-")
      ->
      (match schema_path with
       | None -> loop (Some path) rules_path excluded_tables rest
       | Some _ -> Error Usage)
    | _ -> Error Usage
  in
  loop None None [] arguments
;;

let exclude_tables excluded_tables schema =
  let tables = Schema_ir.tables schema in
  let has_table (schema_name, table_name) table =
    Option.equal Identifier.equal (Schema_ir.table_schema table) (Some schema_name)
    && Identifier.equal (Schema_ir.table_name table) table_name
  in
  match
    List.find excluded_tables ~f:(fun excluded ->
      not (List.exists tables ~f:(has_table excluded)))
  with
  | Some (schema_name, table_name) ->
    Error
      ("excluded table not found: "
       ^ Identifier.to_string schema_name
       ^ "."
       ^ Identifier.to_string table_name)
  | None ->
    Ok
      (Schema_ir.v
         (List.filter tables ~f:(fun table ->
            not
              (List.exists excluded_tables ~f:(fun excluded -> has_table excluded table)))))
;;

let run { schema_path; rules_path; excluded_tables } =
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
  let%bind schema = exclude_tables excluded_tables schema in
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
