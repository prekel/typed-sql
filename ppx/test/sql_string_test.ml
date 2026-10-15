open! Base
open Typed_sql_pgocaml_ppx

let%test_module "PostgreSQL literal lexer" =
  (module struct
    let strings source =
      Sql.parse ("SELECT id FROM items WHERE name IN (" ^ source ^ ")")
      |> Result.map ~f:(fun parsed ->
        match parsed.Sql.conditions with
        | Some (Sql.In (_, values, false)) ->
          List.map values ~f:(function
            | Sql.String_literal (value, _) -> value
            | _ -> failwith "expected string operand")
        | _ -> failwith "expected a literal IN predicate")
    ;;

    let decoded source expected =
      Result.equal
        (List.equal String.equal)
        (fun (a : Sql.error) b ->
           Int.equal a.offset b.offset && String.equal a.message b.message)
        (strings source)
        (Ok expected)
    ;;

    let%test "ordinary strings keep backslashes" = decoded {sql|'a\nb'|sql} [ "a\\nb" ]

    let%test "escape strings decode standard escapes" =
      decoded {sql|E'\b\f\n\r\t\\\''|sql} [ "\b\012\n\r\t\\'" ]
    ;;

    let%test "lowercase prefix and doubled apostrophes" =
      decoded {sql|e'it''s'|sql} [ "it's" ]
    ;;

    let%test "hexadecimal octal and unknown escapes" =
      decoded {sql|E'\101\x42\q'|sql} [ "ABq" ]
    ;;

    let%test "Unicode escapes and surrogate pairs" =
      decoded {sql|E'\u00e9\U0001f600\uD83D\uDE00'|sql} [ "é😀😀" ]
    ;;

    let%test "newline continuations retain escape mode" =
      decoded "E'a'\n'\\nb'" [ "a\nb" ]
    ;;

    let%test "ordinary newline continuation" = decoded "'a'\n'b'" [ "ab" ]

    let%test "line comments allow newline continuation" =
      decoded "'a' -- comment\n'b'" [ "ab" ]
    ;;

    let%test "block comments prevent continuation" =
      Result.is_error (strings "'a'\n/* comment */'b'")
    ;;

    let%test "same-line strings stay separate tokens" =
      Result.is_error (strings "'a' 'b'")
    ;;

    let%test "anonymous dollar quote is verbatim" =
      decoded
        {sql|$$' \n /* */ $name ${expression}$$|sql}
        [ "' \\n /* */ $name ${expression}" ]
    ;;

    let%test "dollar tags are case sensitive" =
      decoded {sql|$Tag$a$tag$b$Tag$|sql} [ "a$tag$b" ]
    ;;

    let%test "dollar tags can contain digits and underscores" =
      decoded {sql|$_tag42$a$other$b$_tag42$|sql} [ "a$other$b" ]
    ;;

    let%test "unterminated tagged string offset" =
      match Sql.parse "SELECT $tag$missing" with
      | Error error ->
        Int.equal error.offset 7
        && String.equal error.message "unterminated dollar-quoted string"
      | Ok _ -> false
    ;;

    let%test "invalid Unicode escape is rejected" =
      Result.is_error (strings {sql|E'\u12x4'|sql})
    ;;

    let%test "unpaired surrogate is rejected" =
      Result.is_error (strings {sql|E'\uD800'|sql})
    ;;

    let%test "zero byte is rejected" = Result.is_error (strings {sql|E'\000'|sql})

    let%test "out of range Unicode is rejected" =
      Result.is_error (strings {sql|E'\U00110000'|sql})
    ;;

    let%test "unterminated escape string is rejected" =
      Result.is_error (strings "E'abc\\")
    ;;

    let%test_unit "literal text and bind offsets are preserved" =
      let source = {sql|SELECT $tag$${fake} $@ids$tag$, E'\n$fake', $real::integer|sql} in
      let plan =
        let open Result.Let_syntax in
        let%bind parsed = Sql.parse source in
        Statement_plan.create (Typed_sql_schema.Schema_ir.v []) parsed
      in
      let plan =
        plan |> Result.map_error ~f:Sql.error_to_string |> Result.ok_or_failwith
      in
      assert (
        String.equal
          plan.sql
          {sql|SELECT $tag$${fake} $@ids$tag$, E'\n$fake', $1::integer|sql});
      let parameter = List.hd_exn plan.parameters in
      assert (String.equal parameter.value.expression "real");
      assert (
        Int.equal parameter.value.start (String.substr_index_exn source ~pattern:"$real"))
    ;;
  end)
;;
