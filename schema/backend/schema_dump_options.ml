open! Base
open Typed_sql_schema

type options =
  { uri : string option
  ; excluded_tables : (Identifier.t * Identifier.t) list
  }

type argument_error =
  | Help
  | Usage

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
  let rec loop uri excluded_tables = function
    | [] -> Ok { uri; excluded_tables = List.rev excluded_tables }
    | [ "--help" ] | [ "-h" ] -> Error Help
    | "--exclude-table" :: table_name :: rest ->
      (match parse_qualified_table table_name with
       | Error _ -> Error Usage
       | Ok table -> loop uri (table :: excluded_tables) rest)
    | "--exclude-table" :: [] -> Error Usage
    | uri_arg :: rest
      when (not (String.is_prefix uri_arg ~prefix:"-")) && Option.is_none uri ->
      loop (Some uri_arg) excluded_tables rest
    | _ -> Error Usage
  in
  loop None [] arguments
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
