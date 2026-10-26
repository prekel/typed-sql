open! Base
module P = Typed_sql_pgocaml_ppx
module C = P.Query_cache
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

let%test_module "query cache custom converters" =
  (module struct
    let typ ?(schema = "public") name kind =
      { S.schema = I.of_string_exn schema; name = I.of_string_exn name; kind }
    ;;

    let text = typ ~schema:"pg_catalog" "text" Native_scalar
    let int4 = typ ~schema:"pg_catalog" "int4" Native_scalar
    let domain = typ "typ123" (Native_domain text)

    let cache typ =
      C.create
        ~role:"fixture"
        ~search_path:"public"
        [ { C.sql = "SELECT $1"
          ; kind = C.Select
          ; top_level_only = false
          ; parameters = [ typ ]
          ; result = Some [ { C.name = "value"; typ; nullable = true } ]
          }
        ]
    ;;

    let plan cache =
      let open Result.Let_syntax in
      let%bind cache = cache in
      let%bind query =
        P.Query_bind.scan "SELECT $?value"
        |> Result.map_error ~f:P.Query_bind.error_to_string
      in
      C.plan cache query |> Result.map_error ~f:P.Query_bind.error_to_string
    ;;

    let uses typ expected =
      let round_trip =
        let open Result.Let_syntax in
        let%bind cache = cache typ in
        C.of_string (C.to_string cache)
      in
      match plan round_trip with
      | Ok { parameters = [ parameter ]; result = Rows [ field ]; _ } ->
        String.equal (P.Codec.to_string parameter.codec) expected
        && String.equal (P.Codec.to_string field.codec) expected
      | _ -> false
    ;;

    let%test "text domains use their own converter" = uses domain "typ123"

    let%test "integer domains use their own converter" =
      uses (typ "number123" (Native_domain int4)) "number123"
    ;;

    let%test "enums use their own converter" =
      uses (typ "mood123" (Native_enum [ "ready"; "done" ])) "mood123"
    ;;

    let%test "user-defined scalar types use their own converter" =
      uses (typ "scalar123" Native_scalar) "scalar123"
    ;;

    let%test "opaque types survive serialization" =
      uses (typ "record123" Native_opaque) "record123"
    ;;

    let%test "arrays use their element converter" =
      uses (typ "_typ123" (Native_array domain)) "typ123 option list"
    ;;

    let%test "domains over arrays use the domain converter" =
      uses (typ "list123" (Native_domain (typ "_typ123" (Native_array domain)))) "list123"
    ;;

    let%test "domains can provide a converter for an unsupported base type" =
      uses
        (typ
           "custom123"
           (Native_domain (typ ~schema:"pg_catalog" "unknown123" Native_scalar)))
        "custom123"
    ;;

    let%test "schemas do not qualify converter names" =
      uses (typ ~schema:"another_schema" "typ123" (Native_domain text)) "typ123"
    ;;

    let%test "built-in integer converters retain their PGOCaml names" = uses int4 "int32"
    let%test "built-in text retains its string converter" = uses text "string"

    let%test "unknown built-in codecs remain errors" =
      Result.is_error (cache (typ ~schema:"pg_catalog" "unknown123" Native_scalar))
    ;;

    let uses_domain = function
      | Ok { P.Statement_plan.parameters = [ { codec = Scalar "typ123"; _ } ]; _ } -> true
      | _ -> false
    ;;

    let%test "shared metadata selects custom converters without stored codec names" =
      let module Shared = Typed_sql_ppx_cache.Query_cache in
      let shared =
        Shared.create
          ~role:"fixture"
          ~search_path:"public"
          [ { Shared.sql = "SELECT $1"
            ; kind = Shared.Select
            ; top_level_only = false
            ; parameters = [ domain ]
            ; result = Some [ { Shared.name = "value"; typ = domain; nullable = true } ]
            }
          ]
        |> Result.ok_or_failwith
      in
      C.of_string (Shared.to_string shared) |> plan |> uses_domain
    ;;

    let%test "converter suffixes can contain uppercase letters digits and apostrophes" =
      uses (typ "123_Name'" Native_scalar) "123_Name'"
    ;;

    let%test "custom types named like builtins retain their exact name" =
      uses (typ "text" Native_scalar) "text"
    ;;

    let%test "quoted SQL names cannot inject OCaml expressions or paths" =
      List.for_all [ "has space"; "bad.name"; "a()"; "имя" ] ~f:(fun name ->
        Result.is_error (cache (typ name Native_scalar)))
    ;;

    let%expect_test "invalid converter suffixes have an explicit diagnostic" =
      (match cache (typ "bad-name" Native_scalar) with
       | Error message -> Stdlib.print_endline message
       | Ok _ -> failwith "expected an invalid converter name");
      [%expect
        {| PostgreSQL type public.bad-name cannot form an OCaml converter name; expected only ASCII letters, digits, underscores or apostrophes |}]
    ;;
  end)
;;
