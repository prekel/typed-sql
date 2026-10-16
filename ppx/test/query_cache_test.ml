open! Base
module P = Typed_sql_pgocaml_ppx
module C = P.Query_cache
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

let get = function
  | Ok value -> value
  | Error message -> failwith message
;;

let scan source =
  P.Query_bind.scan source |> Result.map_error ~f:P.Sql.error_to_string |> get
;;

let scalar name =
  { S.schema = I.of_string_exn "pg_catalog"
  ; name = I.of_string_exn name
  ; kind = S.Native_scalar
  }
;;

let int4 = scalar "int4"

let entry =
  { C.sql = "SELECT $1::int4 AS id"
  ; parameters = [ int4 ]
  ; result = Some [ { C.name = "id"; typ = int4; nullable = true } ]
  }
;;

let cache = C.create ~role:"fixture" ~search_path:"public" [ entry ] |> get

let%expect_test "rewrite occurrences independently without parsing SQL" =
  let query =
    scan "SELECT $id::int4 # $id, $?{Some 1l} ~ ${String.concat [\"a\"; \"}\"]}"
  in
  Stdlib.print_endline query.sql;
  [%expect {| SELECT $1::int4 # $2, $3 ~ $4 |}]
;;

let%test "strings identifiers comments and dollar quotes keep substitutions literal" =
  let sql =
    {sql|SELECT '$ignored', E'it\'s $ignored', "$ignored", foo$bar, $$ $ignored $$, $tag$ $ignored $tag$ /* $ignored /* $nested */ */ -- $ignored
WHERE id = $id|sql}
  in
  let query = scan sql in
  Int.equal (List.length query.parameters) 1
  && String.equal
       query.sql
       (String.substr_replace_first sql ~pattern:"= $id" ~with_:"= $1")
;;

let%test "Unicode SQL identifiers may contain dollar signs" =
  String.equal (scan "SELECT имя$суффикс, $value").sql "SELECT имя$суффикс, $1"
;;

let%test "optional and braced expressions preserve current bindings" =
  match (scan "SELECT $?value, ${ { contents = \"}\" }.contents }").parameters with
  | [ first; second ] ->
    first.optional && (not second.optional) && String.equal first.expression "value"
  | _ -> false
;;

let%test "list substitutions remain deferred" =
  Result.is_error (P.Query_bind.scan "SELECT $@ids")
;;

let%test "native positional parameters are rejected" =
  Result.is_error (P.Query_bind.scan "SELECT $1")
;;

let%test "unterminated block comments are rejected" =
  Result.is_error (P.Query_bind.scan "SELECT /*")
;;

let%test "unterminated strings are rejected" =
  Result.is_error (P.Query_bind.scan "SELECT '$id")
;;

let%test "unterminated dollar quotes are rejected" =
  Result.is_error (P.Query_bind.scan "SELECT $tag$ $id")
;;

let%test "invalid OCaml expressions are rejected" =
  Result.is_error (P.Query_bind.scan "SELECT ${let}")
;;

let%test "cache round trip is deterministic" =
  let json = C.to_string cache in
  String.equal (C.of_string json |> get |> C.to_string) json
;;

let%test "bindings are recovered from current source rather than the cache" =
  match C.plan cache (scan "SELECT $?other::int4 AS id") with
  | Ok { parameters = [ parameter ]; _ } ->
    parameter.value.optional && String.equal parameter.value.expression "other"
  | _ -> false
;;

let%expect_test "missing metadata explains how to regenerate" =
  (match C.plan cache (scan "SELECT 2") with
   | Ok _ -> failwith "unexpected cached query"
   | Error error -> Stdlib.print_endline error.message);
  [%expect
    {| query is absent from the cache; run typed-sql-pgocaml-queries prepare to refresh it |}]
;;

let%test "parameter arity is checked" =
  Result.is_error (C.plan cache { P.Query_bind.sql = entry.sql; parameters = [] })
;;

let%test "unsupported cache versions are rejected" =
  Result.is_error
    (C.of_string
       (String.substr_replace_first
          (C.to_string cache)
          ~pattern:"\"version\": 1"
          ~with_:"\"version\": 3"))
;;

let%test "cached codec must match logical type" =
  Result.is_error
    (C.of_string
       (String.substr_replace_first
          (C.to_string cache)
          ~pattern:"\"codec\": \"int32\""
          ~with_:"\"codec\": \"arbitrary_function\""))
;;

let%test "duplicate SQL is rejected" =
  Result.is_error (C.create ~role:"fixture" ~search_path:"public" [ entry; entry ])
;;

let%test "zero-column rows are rejected" =
  Result.is_error
    (C.create ~role:"fixture" ~search_path:"public" [ { entry with result = Some [] } ])
;;

let%test "opaque scalar codecs are rejected" =
  Result.is_error
    (C.create
       ~role:"fixture"
       ~search_path:"public"
       [ { entry with parameters = [ scalar "unknown" ] } ])
;;

let%test "entry ordering does not depend on source traversal order" =
  let other = { entry with sql = "SELECT $1::int4 AS other" } in
  let make entries =
    C.create ~role:"fixture" ~search_path:"public" entries |> get |> C.to_string
  in
  String.equal (make [ entry; other ]) (make [ other; entry ])
;;

let%test "collector finds ordinary and delimited literals in nested expressions" =
  let source =
    {ocaml|let find dbh id =
    let a = [%pgsql dbh "SELECT $id"] in
    List.map a ~f:(fun _ -> [%pgsql.object dbh "nullable-results" {sql|SELECT $id AS id|sql}])|ocaml}
  in
  let lexbuf = Stdlib.Lexing.from_string source in
  Ppxlib.Location.init lexbuf "fixture.ml";
  match P.Query_source.collect_exn (Ppxlib.Parse.implementation lexbuf) with
  | [ first; second ] ->
    String.equal first.query.sql "SELECT $1"
    && String.equal second.query.sql "SELECT $1 AS id"
    && String.equal first.loc.loc_start.pos_fname "fixture.ml"
  | _ -> false
;;

let%test "collector validates flags before preparing SQL" =
  Result.is_error
    (Result.try_with (fun () ->
       Ppxlib.Parse.implementation
         (Stdlib.Lexing.from_string
            {ocaml|let q dbh = [%pgsql dbh "load_custom_from=config.sexp" "SELECT 1"]|ocaml})
       |> P.Query_source.collect_exn))
;;

let%test "escape mode carries across newline-separated string segments" =
  let source =
    {sql|SELECT E'first'
'it\'s $ignored', $value|sql}
  in
  String.equal
    (scan source).sql
    (String.substr_replace_first source ~pattern:"$value" ~with_:"$1")
;;

let%test "missing result is not silently interpreted as a command" =
  Result.is_error
    (C.of_string
       {json|{"version":1,"role":"fixture","search_path":"public","queries":[{"sql":"SELECT 1","parameters":[]}]}|json})
;;

let%test "logical v2 metadata derives legacy PGOCaml codecs" =
  let module Shared = Typed_sql_ppx_cache.Query_cache in
  match
    Shared.create
      ~role:"fixture"
      ~search_path:"public"
      [ { Shared.sql = entry.sql
        ; kind = Shared.Select
        ; top_level_only = false
        ; parameters = entry.parameters
        ; result = Some [ { Shared.name = "id"; typ = int4; nullable = true } ]
        }
      ]
  with
  | Error _ -> false
  | Ok cache -> Result.is_ok (C.of_string (Shared.to_string cache))
;;
