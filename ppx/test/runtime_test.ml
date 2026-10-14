open! Base
module R = Typed_sql_pgocaml_runtime

let%test_module "native array wire format" =
  (module struct
    let decode value = R.array_of_string value |> Result.ok_or_failwith

    let%test_unit "empty arrays are lists without elements" =
      assert (List.is_empty (decode "{}"))
    ;;

    let%test_unit "quoted NULL differs from a NULL element" =
      assert (
        List.equal
          (Option.equal String.equal)
          (decode "{NULL,\"NULL\",\"\"}")
          [ None; Some "NULL"; Some "" ])
    ;;

    let%test_unit "commas braces quotes and backslashes round-trip" =
      let values =
        [ Some "a,b"; Some "{}"; Some "a\"b"; Some "a\\b"; Some " NULL "; None ]
      in
      assert (
        List.equal
          (Option.equal String.equal)
          (decode (R.string_of_array Fn.id values))
          values)
    ;;

    let%test "nested dimensions are rejected" =
      Result.is_error (R.array_of_string "{{1,2},{3,4}}")
    ;;

    let%test "explicit bounds are rejected" =
      Result.is_error (R.array_of_string "[0:1]={1,2}")
    ;;

    let%test "unterminated quotes are rejected" =
      Result.is_error (R.array_of_string "{\"unfinished}")
    ;;

    let%test "empty unquoted elements are rejected" =
      Result.is_error (R.array_of_string "{1,,2}")
    ;;

    let%test "non-array text is rejected" =
      Result.is_error (R.array_of_string "not an array")
    ;;

    let%test "dangling escapes are rejected" =
      Result.is_error (R.array_of_string "{abc\\}")
    ;;

    let%test_unit "whitespace outside quoted elements is ignored" =
      assert (
        List.equal
          (Option.equal String.equal)
          (decode " { \"x\" , NULL } ")
          [ Some "x"; None ])
    ;;
  end)
;;
