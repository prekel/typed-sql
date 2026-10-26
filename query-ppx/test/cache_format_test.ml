open! Base
module C = Typed_sql_ppx_cache.Query_cache
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier
module J = Yojson.Safe.Util

let%test_module "version 3 type dictionary" =
  (module struct
    let typ ?(schema = "public") name kind =
      { S.schema = I.of_string_exn schema; name = I.of_string_exn name; kind }
    ;;

    let text = typ ~schema:"pg_catalog" "text" Native_scalar
    let domain = typ "typ123" (Native_domain text)

    let entry ?(sql = "SELECT $1") typ =
      { C.sql
      ; kind = C.Select
      ; top_level_only = false
      ; parameters = [ typ ]
      ; result = Some [ { C.name = "value"; typ; nullable = true } ]
      }
    ;;

    let create entries = C.create ~role:"fixture" ~search_path:"public" entries
    let cache = create [ entry domain ] |> Result.ok_or_failwith
    let types cache = C.to_string cache |> Yojson.Safe.from_string |> J.member "types"

    let decode definitions ?(parameters = []) () =
      Yojson.Safe.to_string
        (`Assoc
            [ "version", `Int 3
            ; "role", `String "fixture"
            ; "search_path", `String "public"
            ; "types", `Assoc definitions
            ; ( "queries"
              , `List
                  [ `Assoc
                      [ "sql", `String "DELETE FROM t WHERE id = $1"
                      ; "kind", `String "command"
                      ; "top_level_only", `Bool true
                      ; "parameters", `List parameters
                      ; "result", `Null
                      ]
                  ] )
            ])
      |> C.of_string
    ;;

    let scalar = `Assoc [ "kind", `String "scalar" ]
    let domain_ref base = `Assoc [ "kind", `String "domain"; "base", `String base ]

    let print_error result =
      match result with
      | Error message -> Stdlib.print_endline message
      | Ok _ -> failwith "expected an invalid cache"
    ;;

    let%expect_test "readable metadata uses stable named references" =
      Stdlib.print_string (C.to_string cache);
      [%expect
        {|
        {
          "version": 3,
          "role": "fixture",
          "search_path": "public",
          "types": {
            "pg_catalog.text": {"kind": "scalar"},
            "public.typ123": {"kind": "domain", "base": "pg_catalog.text"}
          },
          "queries": [
            {
              "sql": "SELECT $1",
              "kind": "select",
              "top_level_only": false,
              "parameters": ["public.typ123"],
              "result": [
                {"name": "value", "type": "public.typ123", "nullable": true}
              ]
            }
          ]
        }
        |}]
    ;;

    let%test "nested types are defined once across parameters and fields" =
      let array = typ "_typ123" (Native_array domain) in
      let first = entry array in
      let second =
        { first with sql = "SELECT $1 AS other"; parameters = [ array; domain; text ] }
      in
      let cache = create [ second; first ] |> Result.ok_or_failwith in
      List.length (types cache |> J.to_assoc) |> Int.equal 3
    ;;

    let%test "adding an unrelated type preserves existing dictionary entries" =
      let other = typ ~schema:"another" "flag" Native_scalar in
      let extended =
        create [ entry domain; entry ~sql:"SELECT $1 AS other" other ]
        |> Result.ok_or_failwith
      in
      List.for_all
        (types cache |> J.to_assoc)
        ~f:(fun (key, value) -> Yojson.Safe.equal value (types extended |> J.member key))
    ;;

    let%test "forward references resolve independently of dictionary order" =
      match
        decode
          [ "a.domain", domain_ref "z.scalar"; "z.scalar", scalar ]
          ~parameters:[ `String "a.domain" ]
          ()
      with
      | Ok cache ->
        (match (List.hd_exn (C.entries cache)).parameters with
         | [ { kind = Native_domain { schema; name; kind = Native_scalar }; _ } ] ->
           I.equal schema (I.of_string_exn "z") && I.equal name (I.of_string_exn "scalar")
         | _ -> false)
      | Error _ -> false
    ;;

    let%test "quoted identifiers do not collide across schema and type boundaries" =
      let left = typ ~schema:"a.b" "odd\"name" Native_scalar in
      let right = typ ~schema:"a" "b.odd\"name" Native_scalar in
      let entry = { (entry left) with parameters = [ left; right ] } in
      let cache = create [ entry ] |> Result.ok_or_failwith in
      let restored = C.of_string (C.to_string cache) |> Result.ok_or_failwith in
      Int.equal (List.length (types restored |> J.to_assoc)) 2
      && String.equal (C.to_string cache) (C.to_string restored)
    ;;

    let%test "enum labels and SQL bytes retain unicode quotes and escapes" =
      let enum = typ ~schema:"Case" "odd.λ" (Native_enum [ "ready"; "λ\"\\\n" ]) in
      let cache =
        create [ entry ~sql:"SELECT $1 AS \"λ\" /* \" \\ */" enum ]
        |> Result.ok_or_failwith
      in
      let json = C.to_string cache in
      String.equal json (C.of_string json |> Result.ok_or_failwith |> C.to_string)
    ;;

    let%expect_test "conflicting nominal definitions are rejected" =
      let left = typ "status" (Native_enum [ "ready" ]) in
      let right = typ "status" (Native_enum [ "done" ]) in
      print_error (create [ { (entry left) with parameters = [ left; right ] } ]);
      [%expect {| conflicting query cache type definition: public.status |}]
    ;;

    let%expect_test "duplicate type dictionary keys are rejected" =
      print_error (decode [ "public.value", scalar; "public.value", scalar ] ());
      [%expect {| duplicate query cache type definition: public.value |}]
    ;;

    let%expect_test "unknown nested type references are rejected" =
      print_error (decode [ "public.value", domain_ref "public.missing" ] ());
      [%expect {| unknown query cache type reference: public.missing |}]
    ;;

    let%expect_test "unknown parameter type references are rejected" =
      print_error (decode [] ~parameters:[ `String "public.missing" ] ());
      [%expect {| unknown query cache type reference: public.missing |}]
    ;;

    let%expect_test "cyclic definitions are rejected even when unused" =
      print_error (decode [ "public.value", domain_ref "public.value" ] ());
      [%expect {| cyclic query cache type reference: public.value |}]
    ;;

    let%test "indirect array domain cycles are rejected" =
      Result.is_error
        (decode
           [ "public.value", domain_ref "public.array"
           ; ( "public.array"
             , `Assoc [ "kind", `String "array"; "element", `String "public.value" ] )
           ]
           ())
    ;;

    let%test "ambiguous and noncanonical qualified keys are rejected" =
      List.for_all
        [ "unqualified"; "a.b.c"; "\"a\".b"; "a.\"unterminated"; "a." ]
        ~f:(fun key -> Result.is_error (decode [ key, scalar ] ()))
    ;;

    let%test "type references must be strings" =
      Result.is_error (decode [ "public.value", scalar ] ~parameters:[ `Int 0 ] ())
    ;;

    let chain depth =
      ("public.t0", scalar)
      :: List.init depth ~f:(fun index ->
        ( "public.t" ^ Int.to_string (index + 1)
        , domain_ref ("public.t" ^ Int.to_string index) ))
    ;;

    let%test "64 nested type edges are accepted" = Result.is_ok (decode (chain 64) ())

    let%test "cached subtree heights cannot bypass the depth limit" =
      Result.is_error (decode (chain 65) ())
    ;;

    let%test "typed construction checks nesting before serialization" =
      let nested =
        List.fold (List.init 65 ~f:Fn.id) ~init:text ~f:(fun base index ->
          typ ("t" ^ Int.to_string index) (Native_domain base))
      in
      Result.is_error (create [ entry nested ])
    ;;

    let%test "the index distinguishes exact SQL and preserves sorted entries" =
      let entries =
        List.init 100 ~f:(fun index ->
          entry ~sql:("SELECT $1 AS value" ^ Int.to_string index) text)
      in
      let cache = create (List.rev entries) |> Result.ok_or_failwith in
      Option.is_none (C.find cache ~sql:"SELECT $1 AS missing")
      && Option.value_map
           (C.find cache ~sql:"SELECT $1 AS value17")
           ~default:false
           ~f:(fun entry -> String.equal entry.sql "SELECT $1 AS value17")
      && List.is_sorted (C.entries cache) ~compare:(fun left right ->
        String.compare left.sql right.sql)
    ;;

    let embedded_json target =
      let source = C.codegen ~target cache in
      let structure = Ppxlib.Parse.implementation (Stdlib.Lexing.from_string source) in
      let values = ref [] in
      let visitor =
        object
          inherit Ppxlib.Ast_traverse.iter as super

          method! expression expression =
            (match expression.pexp_desc with
             | Pexp_constant (Pconst_string (value, _, _))
               when String.is_prefix value ~prefix:"{\"version\":" ->
               values := value :: !values
             | _ -> ());
            super#expression expression
        end
      in
      visitor#structure structure;
      match !values with
      | [ value ] -> value
      | _ -> failwith "expected exactly one embedded cache literal"
    ;;

    let compact target =
      let source = embedded_json target in
      (not (String.contains source '\n'))
      && Int.(String.length source < String.length (C.to_string cache))
      && String.equal
           (C.to_string cache)
           (C.of_string source |> Result.ok_or_failwith |> C.to_string)
    ;;

    let%test "PGOCaml codegen embeds compact metadata" = compact `Pgocaml_ppx
    let%test "typed query codegen embeds compact metadata" = compact `Typed_sql_ppx

    let%test "a thousand wide queries fit in a two MiB readable cache" =
      let fields =
        List.init 16 ~f:(fun index ->
          { C.name = "field" ^ Int.to_string index; typ = text; nullable = true })
      in
      let entries =
        List.init 1000 ~f:(fun index ->
          { (entry ~sql:("SELECT $1 AS value" ^ Int.to_string index) text) with
            result = Some fields
          })
      in
      let cache = create entries |> Result.ok_or_failwith in
      Int.(String.length (C.to_string cache) < 2 * 1024 * 1024)
    ;;
  end)
;;
