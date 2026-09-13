open! Base
open Typed_sql

let run path =
  let open Result.Let_syntax in
  let%bind source =
    try
      Ok
        (if String.equal path "-" then
           Stdlib.In_channel.input_all Stdlib.stdin
         else
           Stdlib.In_channel.with_open_bin path Stdlib.In_channel.input_all)
    with
    | Sys_error message -> Error message
  in
  let%bind schema =
    Schema_snapshot.of_string source
    |> Result.map_error ~f:Schema_snapshot.error_to_string
  in
  Schema_codegen.generate schema |> Result.map_error ~f:Schema_codegen.error_to_string
;;

let () =
  match Stdlib.Sys.argv with
  | [| _; "--help" | "-h" |] ->
    Stdlib.print_endline "Usage: typed-sql-codegen SCHEMA.json|-"
  | [| _; path |] ->
    (match run path with
     | Ok source -> Stdlib.print_string source
     | Error message ->
       Stdlib.prerr_endline ("typed-sql-codegen: " ^ message);
       Stdlib.exit 1)
  | _ ->
    Stdlib.prerr_endline "Usage: typed-sql-codegen SCHEMA.json|-";
    Stdlib.exit 2
;;
