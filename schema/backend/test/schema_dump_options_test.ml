open! Base
open Typed_sql_schema
module Options = Typed_sql_schema_backend.Schema_dump_options

let identifier = Identifier.of_string_exn
let qualified schema table = identifier schema, identifier table

let equal_qualified (left_schema, left_table) (right_schema, right_table) =
  Identifier.equal left_schema right_schema && Identifier.equal left_table right_table
;;

let%test_module "table filter arguments" =
  (module struct
    let usage_error arguments =
      match Options.parse_args arguments with
      | Error Usage -> true
      | Error Help | Ok _ -> false
    ;;

    let%test "repeated filters and URI preserve argument order" =
      let options =
        Options.parse_args
          [ "--include-table"
          ; "public.child"
          ; "postgresql://localhost/app"
          ; "--exclude-table"
          ; "archive.parent"
          ; "--include-table"
          ; "public.parent"
          ]
        |> function
        | Ok options -> options
        | Error _ -> failwith "valid table filters were rejected"
      in
      Option.equal String.equal options.uri (Some "postgresql://localhost/app")
      && List.equal
           equal_qualified
           options.included_tables
           [ qualified "public" "child"; qualified "public" "parent" ]
      && List.equal
           equal_qualified
           options.excluded_tables
           [ qualified "archive" "parent" ]
    ;;

    let%test "quoted identifiers retain dots, spaces and escaped quotes" =
      match
        Options.parse_args [ "--include-table"; "\"schema.with.dot\".\"table\"\" name\"" ]
      with
      | Ok options ->
        List.equal
          equal_qualified
          options.included_tables
          [ qualified "schema.with.dot" "table\" name" ]
      | Error _ -> false
    ;;

    let%test "missing inclusion value is invalid usage" =
      usage_error [ "--include-table" ]
    ;;

    let%test "unqualified inclusion is invalid usage" =
      usage_error [ "--include-table"; "child" ]
    ;;

    let%test "unterminated quoted inclusion is invalid usage" =
      usage_error [ "--include-table"; "public.\"child" ]
    ;;

    let%test "empty inclusion identifier is invalid usage" =
      usage_error [ "--include-table"; "public.\"\"" ]
    ;;
  end)
;;

let%test_module "table selection" =
  (module struct
    let table ?schema ?(foreign_keys = []) name =
      Schema_ir.table
        ?schema:(Option.map schema ~f:identifier)
        ~name:(identifier name)
        ~columns:
          [ Schema_ir.column ~name:(identifier "id") ~db_type:Int ~nullable:false () ]
        ~foreign_keys
        ()
    ;;

    let parent = table ~schema:"public" "parent"

    let child =
      table
        ~schema:"public"
        ~foreign_keys:
          [ Schema_ir.foreign_key
              ~columns:[ identifier "id" ]
              ~referenced_schema:(identifier "public")
              ~referenced_table:(identifier "parent")
              ~referenced_columns:[ identifier "id" ]
              ()
          ]
        "child"
    ;;

    let archived = table ~schema:"archive" "parent"
    let unqualified = table "parent"
    let schema = Schema_ir.v [ parent; child; archived; unqualified ]

    let select ?(include_ = []) ?(exclude = []) () =
      Options.filter_tables ~included_tables:include_ ~excluded_tables:exclude schema
    ;;

    let selects result tables =
      match result with
      | Error _ -> false
      | Ok selected ->
        String.equal
          (Schema_snapshot.to_string selected)
          (Schema_snapshot.to_string (Schema_ir.v tables))
    ;;

    let%test "no filters preserve the full snapshot" =
      selects (select ()) [ parent; child; archived; unqualified ]
    ;;

    let%test "multiple inclusions preserve source order" =
      selects
        (select
           ~include_:[ qualified "archive" "parent"; qualified "public" "parent" ]
           ())
        [ parent; archived ]
    ;;

    let%test "duplicate inclusions do not duplicate tables" =
      selects
        (select ~include_:[ qualified "public" "parent"; qualified "public" "parent" ] ())
        [ parent ]
    ;;

    let%test "inclusion uses exact schema-qualified identity" =
      selects (select ~include_:[ qualified "public" "parent" ] ()) [ parent ]
    ;;

    let%test "exclusion wins over inclusion" =
      selects
        (select
           ~include_:[ qualified "public" "parent"; qualified "public" "child" ]
           ~exclude:[ qualified "public" "parent" ]
           ())
        [ child ]
    ;;

    let%test "exclusions are validated before inclusion filtering" =
      selects
        (select
           ~include_:[ qualified "public" "child" ]
           ~exclude:[ qualified "archive" "parent" ]
           ())
        [ child ]
    ;;

    let%test "all included tables can be excluded" =
      selects
        (select
           ~include_:[ qualified "public" "parent" ]
           ~exclude:[ qualified "public" "parent" ]
           ())
        []
    ;;

    let%test "FK metadata survives without implicitly including the referenced table" =
      selects (select ~include_:[ qualified "public" "child" ] ()) [ child ]
    ;;

    let%expect_test "unknown inclusion is an error" =
      select ~include_:[ qualified "public" "missing" ] ()
      |> Result.iter_error ~f:Stdlib.print_endline;
      [%expect {| included table not found: public.missing |}]
    ;;

    let%expect_test "unknown exclusion is an error even outside the inclusion set" =
      select
        ~include_:[ qualified "public" "child" ]
        ~exclude:[ qualified "archive" "missing" ]
        ()
      |> Result.iter_error ~f:Stdlib.print_endline;
      [%expect {| excluded table not found: archive.missing |}]
    ;;

    let%expect_test "an inclusion cannot be rescued by an identical exclusion" =
      select
        ~include_:[ qualified "public" "missing" ]
        ~exclude:[ qualified "public" "missing" ]
        ()
      |> Result.iter_error ~f:Stdlib.print_endline;
      [%expect {| included table not found: public.missing |}]
    ;;
  end)
;;
