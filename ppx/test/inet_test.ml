open! Base
module P = Typed_sql_pgocaml_ppx
module C = P.Query_cache
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

let%test_module "native inet codecs" =
  (module struct
    let inet =
      { S.schema = I.of_string_exn "pg_catalog"
      ; name = I.of_string_exn "inet"
      ; kind = S.Native_scalar
      }
    ;;

    let codec typ =
      let sql = "SELECT $1" in
      let entry =
        { C.sql
        ; kind = C.Select
        ; top_level_only = false
        ; parameters = [ typ ]
        ; result = Some [ { C.name = "address"; typ; nullable = true } ]
        }
      in
      let cache =
        C.create ~role:"fixture" ~search_path:"public" [ entry ]
        |> Result.ok_or_failwith
        |> C.to_string
        |> C.of_string
        |> Result.ok_or_failwith
      in
      let query =
        P.Query_bind.scan "SELECT $?address"
        |> Result.map_error ~f:P.Query_bind.error_to_string
        |> Result.ok_or_failwith
      in
      C.plan cache query
      |> Result.map_error ~f:P.Query_bind.error_to_string
      |> Result.ok_or_failwith
    ;;

    let has_inet_codecs typ =
      match codec typ with
      | { parameters = [ { codec = Scalar "inet"; _ } ]
        ; result = Rows [ { codec = Scalar "inet"; nullable = true; _ } ]
        ; _
        } -> true
      | _ -> false
    ;;

    let%test "inet uses the PGOCaml inet encoder and decoder" = has_inet_codecs inet

    let%test "domains use their own converter instead of the builtin inet codec" =
      match
        codec
          { S.schema = I.of_string_exn "public"
          ; name = I.of_string_exn "host_address"
          ; kind = S.Native_domain inet
          }
      with
      | { parameters = [ { codec = Scalar "host_address"; _ } ]
        ; result = Rows [ { codec = Scalar "host_address"; nullable = true; _ } ]
        ; _
        } -> true
      | _ -> false
    ;;

    let%test "inet arrays retain nullable element codecs" =
      match
        codec { inet with name = I.of_string_exn "_inet"; kind = Native_array inet }
      with
      | { parameters = [ { codec = Array (Scalar "inet"); _ } ]
        ; result = Rows [ { codec = Array (Scalar "inet"); nullable = true; _ } ]
        ; _
        } -> true
      | _ -> false
    ;;
  end)
;;
