open! Base
open Typed_sql

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

let run path rules_path =
  let open Result.Let_syntax in
  let%bind source = read path in
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
  Schema_codegen.generate ~rules schema
  |> Result.map_error ~f:Schema_codegen.error_to_string
;;

let () =
  match Stdlib.Sys.argv with
  | [| _; "--help" | "-h" |] ->
    Stdlib.print_endline
      "Usage: typed-sql-codegen [--type-rules RULES.json] SCHEMA.json|-"
  | [| _; path |] ->
    (match run path None with
     | Ok source -> Stdlib.print_string source
     | Error message ->
       Stdlib.prerr_endline ("typed-sql-codegen: " ^ message);
       Stdlib.exit 1)
  | [| _; "--type-rules"; rules_path; path |] ->
    (match run path (Some rules_path) with
     | Ok source -> Stdlib.print_string source
     | Error message ->
       Stdlib.prerr_endline ("typed-sql-codegen: " ^ message);
       Stdlib.exit 1)
  | _ ->
    Stdlib.prerr_endline
      "Usage: typed-sql-codegen [--type-rules RULES.json] SCHEMA.json|-";
    Stdlib.exit 2
;;
