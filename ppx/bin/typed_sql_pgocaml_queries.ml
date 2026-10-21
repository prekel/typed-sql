(* The result-nullability heuristic follows PG'OCaml 4.4.0 ppx_pgsql.ml.
   Copyright (C) 2005-2016 Richard Jones and other authors.
   Distributed under the GNU Library General Public License, version 2 or later.
   See ../COPYING and ../ORIGIN.md. *)
open! Base
module P = Typed_sql_ppx_cache
module C = P.Query_cache
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

exception Invalid of string

let reject message = Stdlib.raise (Invalid message)

let get = function
  | Ok value -> value
  | Error message -> reject message
;;

let read_file path =
  let channel = Stdlib.open_in_bin path in
  Exn.protect
    ~finally:(fun () -> Stdlib.close_in channel)
    ~f:(fun () -> Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
;;

let parse_source ~path contents =
  let lexbuf = Stdlib.Lexing.from_string contents in
  Ppxlib.Location.init lexbuf path;
  Ppxlib.Parse.implementation lexbuf
;;

let load_source ~path input =
  let contents = read_file input in
  (* Let ppxlib validate and migrate binary AST versions, retaining source locations. *)
  let structure =
    if String.is_prefix contents ~prefix:"Caml1999" then (
      match
        Ppxlib.Ast_io.read_binary input
      with
      | Error message -> reject ("preprocessing " ^ path ^ ": " ^ message)
      | Ok input ->
        (match Ppxlib.Ast_io.get_ast input with
         | Impl structure -> structure
         | Intf _ -> reject ("expected an implementation AST: " ^ path)))
    else
      parse_source ~path contents
  in
  let errors =
    object
      inherit Ppxlib.Ast_traverse.iter as super

      method! extension ((name, payload) as extension) =
        if String.equal name.txt "ocaml.error" then (
          let message =
            match payload with
            | PStr
                ({ pstr_desc =
                     Pstr_eval
                       ({ pexp_desc = Pexp_constant (Pconst_string (text, _, _)); _ }, _)
                 ; _
                 }
                :: _) -> text
            | _ -> "preprocessor returned an ocaml.error extension"
          in
          Ppxlib.Location.raise_errorf ~loc:name.loc "%s" message)
        else
          super#extension extension
    end
  in
  errors#structure structure;
  structure
;;

let source ?pp path =
  match pp with
  | None -> parse_source ~path (read_file path)
  | Some command ->
    let temporary = Stdlib.Filename.temp_file "typed-sql-pp-" ".ml" in
    Exn.protect
      ~finally:(fun () -> Stdlib.Sys.remove temporary)
      ~f:(fun () ->
        let command =
          "("
          ^ command
          ^ " "
          ^ Stdlib.Filename.quote path
          ^ ") > "
          ^ Stdlib.Filename.quote temporary
        in
        let status = Stdlib.Sys.command command in
        if not (Int.equal status 0) then
          reject (Printf.sprintf "preprocessing %s failed (exit code %d)" path status);
        load_source ~path temporary)
;;

let sources ?pp paths =
  paths
  |> List.concat_map ~f:(fun path ->
    if not (String.is_suffix path ~suffix:".ml") then
      reject ("expected an .ml source: " ^ path);
    P.Query_source.collect_exn (source ?pp path))
  |> List.dedup_and_sort ~compare:(fun a b ->
    String.compare a.P.Query_source.query.sql b.P.Query_source.query.sql)
;;

let execute conn query params =
  let name = "typed_sql_query_catalog" in
  PGOCaml.prepare conn ~name ~query ();
  Exn.protect
    ~finally:(fun () -> PGOCaml.close_statement conn ~name ())
    ~f:(fun () -> PGOCaml.execute conn ~name ~params ())
;;

let one_value = function
  | [ [ Some value ] ] -> value
  | _ -> reject "PostgreSQL catalog query returned an unexpected result"
;;

let connect () =
  let host, unix_domain_socket_dir =
    match Stdlib.Sys.getenv_opt "PGHOST" with
    | Some host when String.is_prefix host ~prefix:"/" -> None, Some host
    | host -> host, None
  in
  PGOCaml.connect ?host ?unix_domain_socket_dir ()
;;

let describe ~search_path queries =
  let conn = connect () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      PGOCaml.alter conn "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY";
      Exn.protect
        ~finally:(fun () -> PGOCaml.alter conn "ROLLBACK")
        ~f:(fun () ->
          ignore
            (execute
               conn
               "SELECT set_config('search_path', $1, true)"
               [ Some search_path ]
             : PGOCaml.row list);
          ignore
            (execute
               conn
               "SELECT set_config('standard_conforming_strings', 'on', true)"
               []
             : PGOCaml.row list);
          let role = execute conn "SELECT current_user::text" [] |> one_value in
          let types = Hashtbl.create (module Int32) in
          let rec resolve seen oid =
            if List.mem seen oid ~equal:Int32.equal then
              reject "recursive PostgreSQL type is not supported";
            match Hashtbl.find types oid with
            | Some typ -> typ
            | None ->
              let row =
                execute
                  conn
                  "SELECT n.nspname, t.typname, t.typtype::text, t.typbasetype::text, t.typelem::text, t.typcategory::text FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace WHERE t.oid = $1::oid"
                  [ Some (Int32.to_string oid) ]
              in
              let typ =
                match row with
                | [ [ Some schema
                    ; Some name
                    ; Some kind
                    ; Some base
                    ; Some element
                    ; Some category
                    ]
                  ] ->
                  let nested value = resolve (oid :: seen) (Int32.of_string value) in
                  let kind =
                    match kind with
                    | "d" -> S.Native_domain (nested base)
                    | "e" ->
                      let labels =
                        execute
                          conn
                          "SELECT enumlabel FROM pg_catalog.pg_enum WHERE enumtypid = $1::oid ORDER BY enumsortorder"
                          [ Some (Int32.to_string oid) ]
                        |> List.map ~f:(function
                          | [ Some value ] -> value
                          | _ -> reject "invalid enum metadata")
                      in
                      S.Native_enum labels
                    | "b" when String.equal category "A" && not (String.equal element "0")
                      -> S.Native_array (nested element)
                    | "b" -> S.Native_scalar
                    | _ -> S.Native_opaque
                  in
                  { S.schema = I.of_string_exn schema; name = I.of_string_exn name; kind }
                | _ -> reject ("PostgreSQL type not found: " ^ Int32.to_string oid)
              in
              Hashtbl.set types ~key:oid ~data:typ;
              typ
          in
          let nullable (field : PGOCaml.result_description) =
            match field.table, field.column with
            | Some table, Some column ->
              let rows =
                execute
                  conn
                  "SELECT attnotnull FROM pg_catalog.pg_attribute WHERE attrelid = $1::oid AND attnum = $2::int2"
                  [ Some (Int32.to_string table); Some (Int.to_string column) ]
              in
              (match rows with
               | [ [ Some value ] ] -> not (PGOCaml.bool_of_string value)
               | _ -> true)
            | _ -> true
          in
          let entries =
            List.map queries ~f:(fun source ->
              let { P.Query_source.query; loc } = source in
              try
                let name = "typed_sql_query_description" in
                PGOCaml.prepare conn ~name ~query:query.sql ();
                let params, result =
                  Exn.protect
                    ~finally:(fun () -> PGOCaml.close_statement conn ~name ())
                    ~f:(fun () -> PGOCaml.describe_statement conn ~name ())
                in
                if not (Int.equal (List.length params) (List.length query.parameters))
                then
                  reject "described parameter count does not match substitutions";
                let entry =
                  { C.sql = query.sql
                  ; kind =
                      C.kind
                        ~operation:(P.Query_kind.analyze query.sql).operation
                        ~rows:(Option.is_some result)
                  ; top_level_only = (P.Query_kind.analyze query.sql).top_level_only
                  ; parameters =
                      List.map params ~f:(fun p -> resolve [] p.PGOCaml.param_type)
                  ; result =
                      Option.map
                        result
                        ~f:
                          (List.map ~f:(fun field ->
                             { C.name = field.PGOCaml.name
                             ; typ = resolve [] field.field_type
                             ; nullable = nullable field
                             }))
                  }
                in
                ignore (get (C.create ~role ~search_path [ entry ]) : C.t);
                entry
              with
              | exn -> Ppxlib.Location.raise_errorf ~loc "%s" (Exn.to_string exn))
          in
          get (C.create ~role ~search_path entries)))
;;

let write_atomic path contents =
  if Stdlib.Sys.file_exists path && String.equal (read_file path) contents then
    ()
  else (
    let temporary, channel =
      Stdlib.Filename.open_temp_file
        ~temp_dir:(Stdlib.Filename.dirname path)
        ".typed-sql-queries-"
        ".json"
    in
    Exn.protect
      ~finally:(fun () ->
        Stdlib.close_out_noerr channel;
        if Stdlib.Sys.file_exists temporary then
          Stdlib.Sys.remove temporary)
      ~f:(fun () ->
        Stdlib.output_string channel contents;
        Stdlib.close_out channel;
        Stdlib.Sys.rename temporary path))
;;

let usage =
  "Usage: typed-sql-pgocaml-queries (prepare --output CACHE | check --cache CACHE) [--search-path PATH] [--pp COMMAND] FILE.ml...\n       typed-sql-pgocaml-queries codegen [--target typed-sql-ppx] CACHE"
;;

let run () =
  match Array.to_list Stdlib.Sys.argv |> List.tl_exn with
  | [ "codegen"; "--target"; "typed-sql-ppx"; path ] ->
    let cache = read_file path |> C.of_string |> get in
    Stdlib.print_string (C.codegen ~target:`Typed_sql_ppx cache)
  | [ "codegen"; path ] ->
    let cache = read_file path |> C.of_string |> get in
    Stdlib.print_string (C.codegen ~target:`Pgocaml_ppx cache)
  | (("prepare" | "check") as command) :: arguments ->
    let rec options cache search_path pp paths = function
      | [] ->
        (match cache, List.rev paths with
         | Some cache, (_ :: _ as paths) -> cache, search_path, pp, paths
         | _ -> reject usage)
      | "--search-path" :: value :: rest -> options cache value pp paths rest
      | "--pp" :: command :: rest ->
        if Option.is_some pp then
          reject "preprocessor specified more than once";
        if String.is_empty (String.strip command) then
          reject "preprocessor command must not be empty";
        options cache search_path (Some command) paths rest
      | flag :: value :: rest
        when String.equal
               flag
               (if String.equal command "prepare" then
                  "--output"
                else
                  "--cache") ->
        if Option.is_some cache then
          reject "cache path specified more than once";
        options (Some value) search_path pp paths rest
      | path :: rest when not (String.is_prefix path ~prefix:"-") ->
        options cache search_path pp (path :: paths) rest
      | _ -> reject usage
    in
    let cache, search_path, pp, paths = options None "public" None [] arguments in
    let queries = sources ?pp paths in
    let expected =
      if String.equal command "check" then
        Some (read_file cache |> C.of_string |> get |> C.to_string)
      else
        None
    in
    let actual = describe ~search_path queries |> C.to_string in
    (match expected with
     | None -> write_atomic cache actual
     | Some expected ->
       if not (String.equal expected actual) then
         reject
           "query cache is stale; run typed-sql-pgocaml-queries prepare to refresh it")
  | _ -> reject usage
;;

let () =
  try run () with
  | Invalid message ->
    Stdlib.prerr_endline message;
    Stdlib.exit 1
  | exn ->
    (match Ppxlib.Location.Error.of_exn exn with
     | Some _ -> Ppxlib.Location.report_exception Stdlib.Format.err_formatter exn
     | None -> Stdlib.prerr_endline (Exn.to_string exn));
    Stdlib.exit 1
;;
