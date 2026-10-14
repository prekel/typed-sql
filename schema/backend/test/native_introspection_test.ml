open! Base
module S = Typed_sql_schema_backend.Schema_introspection
module I = Typed_sql_schema.Identifier

let%test_module "exact catalog type trees" =
  (module struct
    let rows : S.raw_type list =
      [ 21, "pg_catalog", "int2", ("b", 0, 0, "[]")
      ; 23, "pg_catalog", "int4", ("b", 0, 0, "[]")
      ; 1007, "pg_catalog", "_int4", ("b", 0, 23, "[]")
      ; 9000, "public", "small", ("d", 21, 0, "[]")
      ; 9001, "public", "nested", ("d", 9000, 0, "[]")
      ; 9002, "public", "mood", ("e", 0, 0, "[\"sad\",\"happy\"]")
      ; 9003, "public", "_mood", ("b", 0, 9002, "[]")
      ; 9004, "public", "other", ("c", 0, 0, "[]")
      ]
    ;;

    let info oid =
      S.postgresql_type_info rows oid
      |> Result.map_error ~f:(function S.Schema message -> message)
      |> Result.ok_or_failwith
      |> Option.value_exn
    ;;

    let%test_unit "nested domains retain int2 rather than the portable Int" =
      match (info "9001").kind with
      | Native_domain { kind = Native_domain { name; schema; kind = Native_scalar }; _ }
        ->
        assert (
          String.equal (I.to_string name) "int2"
          && String.equal (I.to_string schema) "pg_catalog")
      | _ -> failwith "expected exact nested domain base"
    ;;

    let%test_unit "arrays retain the exact enum identity and label order" =
      match (info "9003").kind with
      | Native_array { schema; name; kind = Native_enum labels } ->
        assert (
          String.equal (I.to_string schema) "public"
          && String.equal (I.to_string name) "mood");
        assert (List.equal String.equal labels [ "sad"; "happy" ])
      | _ -> failwith "expected an enum array"
    ;;

    let%test_unit "opaque catalog types are retained without guessing a codec" =
      match (info "9004").kind with
      | Native_opaque -> ()
      | _ -> failwith "expected an opaque type"
    ;;

    let%test "unknown OIDs are explicit errors" =
      Result.is_error (S.postgresql_type_info rows "9999")
    ;;

    let%test "invalid OIDs are explicit errors" =
      Result.is_error (S.postgresql_type_info rows "not an oid")
    ;;

    let%test "domain cycles are explicit errors" =
      Result.is_error
        (S.postgresql_type_info [ 1, "public", "cycle", ("d", 1, 0, "[]") ] "1")
    ;;

    let%test "missing domain bases are explicit errors" =
      Result.is_error
        (S.postgresql_type_info [ 1, "public", "broken", ("d", 2, 0, "[]") ] "1")
    ;;

    let%test "enum labels must be valid JSON" =
      Result.is_error
        (S.postgresql_type_info [ 1, "public", "broken", ("e", 0, 0, "invalid") ] "1")
    ;;

    let%test "enum labels must be strings" =
      Result.is_error
        (S.postgresql_type_info [ 1, "public", "broken", ("e", 0, 0, "[1]") ] "1")
    ;;

    let%test "enum labels must be an array" =
      Result.is_error
        (S.postgresql_type_info [ 1, "public", "broken", ("e", 0, 0, "{}") ] "1")
    ;;

    let%test "invalid native identifiers are explicit errors" =
      Result.is_error (S.postgresql_type_info [ 1, "public", "", ("b", 0, 0, "[]") ] "1")
    ;;

    let%test_unit "attribute flags are resolved by schema table and column" =
      let rows =
        [ "public", "items", "value", false; "archive", "items", "value", true ]
      in
      assert (
        Option.equal
          Bool.equal
          (S.postgresql_attribute_not_null rows (Some "public") "items" "value")
          (Some false));
      assert (
        Option.is_none
          (S.postgresql_attribute_not_null rows (Some "missing") "items" "value"))
    ;;
  end)
;;
