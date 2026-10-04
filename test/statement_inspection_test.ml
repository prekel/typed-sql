open! Base
open Typed_sql
open Infix

let print_s sexp = Stdlib.print_endline (Sexp.to_string_hum sexp)

let print_parameters (_, (inspection : Statement.inspection)) =
  print_s (Sexp.List (List.map inspection.parameters ~f:Statement.sexp_of_parameter))
;;

let constant_parameter ~dialect db_type value =
  let statement =
    Statement.query_one
      ~dialect:Dialect.portable
      (Query.select_one (Expr.constant db_type value))
  in
  Statement.inspect_exn ~dialect ~input:() statement |> fun (_, inspection) ->
  List.hd_exn inspection.parameters
;;

let%test_module "statement parameter inspection" =
  (module struct
    module Person = struct
      type row

      let table : row Table.t = Table.v_exn "people"
      let id_column = Column.v_exn table "id" Db_type.int64
      let name_column = Column.v_exn table "name" Db_type.text
      let id person = Expr.column person id_column
      let name person = Expr.column person name_column
    end

    type input =
      { id : int64
      ; name : string option
      }

    let statement =
      Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
        let%map.Statement.Parameters id =
          params.column Person.id_column ~get:(fun input -> input.id)
        and name =
          params.optional_expr Db_type.text ~name:"name_filter" ~get:(fun input ->
            input.name)
        in
        params.query_many
          Query.(
            from Person.table
            |> where (fun person -> Person.id person =. id &&. (Person.id person >=. id))
            |> where_optional_param name ~f:(fun person name ->
              Person.name person =. name)
            |> select (fun person -> Projection.expr (Person.id person))))
    ;;

    let input = { id = 7L; name = Some "Ada" }

    let%expect_test "PostgreSQL metadata without input" =
      Statement.inspect_exn ~dialect:Postgresql statement |> print_parameters;
      [%expect
        {|
        (((position 1) (placeholder $1) (name (id)) (db_type int64)
          (dialect_type (bigint)) (value ()))
         ((position 2) (placeholder $2) (name (name_filter)) (db_type "option(text)")
          (dialect_type (text)) (value ())))
        |}]
    ;;

    let%expect_test "SQLite metadata without input" =
      Statement.inspect_exn ~dialect:Sqlite statement |> print_parameters;
      [%expect
        {|
        (((position 1) (placeholder ?1) (name (id)) (db_type int64) (dialect_type ())
          (value ()))
         ((position 2) (placeholder ?2) (name (name_filter)) (db_type "option(text)")
          (dialect_type ()) (value ())))
        |}]
    ;;

    let%expect_test "PostgreSQL bound values" =
      Statement.inspect_exn ~dialect:Postgresql ~input statement |> print_parameters;
      [%expect
        {|
        (((position 1) (placeholder $1) (name (id)) (db_type int64)
          (dialect_type (bigint)) (value ((Encoded 7))))
         ((position 2) (placeholder $2) (name (name_filter)) (db_type "option(text)")
          (dialect_type (text)) (value ((Encoded Ada)))))
        |}]
    ;;

    let%expect_test "SQLite bound values" =
      Statement.inspect_exn ~dialect:Sqlite ~input statement |> print_parameters;
      [%expect
        {|
        (((position 1) (placeholder ?1) (name (id)) (db_type int64)
          (dialect_type (INTEGER)) (value ((Encoded 7))))
         ((position 2) (placeholder ?2) (name (name_filter)) (db_type "option(text)")
          (dialect_type (TEXT)) (value ((Encoded Ada)))))
        |}]
    ;;

    let%test "SQL and inspected placeholders agree" =
      let sql, inspection = Statement.inspect_exn ~dialect:Postgresql ~input statement in
      String.equal sql (Statement.sql_exn ~dialect:Postgresql ~input statement)
      && Int.equal (List.length inspection.parameters) 2
      && Int.equal (String.count sql ~f:(Char.equal '$')) 4
    ;;

    let%test "inspect_exn returns the successful inspection" =
      let sql, inspection = Statement.inspect_exn ~dialect:Postgresql ~input statement in
      String.equal sql (Statement.sql_exn ~dialect:Postgresql ~input statement)
      && Int.equal (List.length inspection.parameters) 2
    ;;

    let%expect_test "query output describes direct columns" =
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql statement in
      print_s (Statement.sexp_of_output inspection.output);
      [%expect
        {|
        (Query_output (cardinality Many)
         (columns
          (((position 1) (name (id)) (db_type int64) (dialect_type (bigint))))))
        |}]
    ;;

    let%test "output column positions follow projection order" =
      let query =
        Query.(
          from Person.table
          |> select (fun person ->
            Projection.pair (Person.name person) (Person.id person)))
      in
      let _, inspection =
        Statement.query_many ~dialect:Dialect.portable query
        |> Statement.inspect_exn ~dialect:Postgresql
      in
      match inspection.output with
      | Statement.Query_output
          { cardinality = `Many
          ; columns =
              [ { position = 1; name = Some "name"; db_type = "text"; _ }
              ; { position = 2; name = Some "id"; db_type = "int64"; _ }
              ]
          } -> true
      | Statement.Query_output _ | Statement.Command_output -> false
    ;;

    let%test "SQL NULL is distinct from missing input" =
      let _, inspection =
        Statement.inspect_exn ~dialect:Sqlite ~input:{ input with name = None } statement
      in
      match List.nth inspection.parameters 1 with
      | Some { value = Some Statement.Null; dialect_type = Some "NULL"; _ } -> true
      | Some _ | None -> false
    ;;

    let%test "an explicit name overrides the column name" =
      let statement =
        Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
          let%map.Statement.Parameters id =
            params.column Person.id_column ~name:"person_id" ~get:Fn.id
          in
          params.query_many
            Query.(
              from Person.table
              |> where (fun person -> Person.id person =. id)
              |> select (fun person -> Projection.expr (Person.id person))))
      in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql statement in
      match inspection.parameters with
      | [ { name = Some "person_id"; _ } ] -> true
      | _ -> false
    ;;

    let%test "command parameters are inspected" =
      let command =
        Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
          let%map.Statement.Parameters id = params.column Person.id_column ~get:Fn.id in
          params.command
            Delete.(
              from Person.table |> where (fun person -> Person.id person =. id) |> command))
      in
      let sql, inspection = Statement.inspect_exn ~dialect:Sqlite ~input:7L command in
      String.equal sql (Statement.sql_exn ~dialect:Sqlite ~input:7L command)
      &&
      match inspection.parameters with
      | [ { placeholder = "?1"
          ; name = Some "id"
          ; value = Some (Statement.Encoded "7")
          ; _
          }
        ] -> true
      | _ -> false
    ;;

    let%test "command output records affected rows" =
      let command =
        Statement.command
          ~dialect:Dialect.portable
          Delete.(from Person.table |> all_rows |> command)
      in
      let _, inspection = Statement.inspect_exn ~dialect:Sqlite command in
      match inspection.output, inspection.tree with
      | Statement.Command_output, Statement.Leaf { kind = `Command; mode = `Static } ->
        (match inspection.dialect with
         | Dialect.Sqlite -> true
         | Dialect.Postgresql -> false)
      | _ -> false
    ;;

    let%expect_test "command output has a structured sexp" =
      let command =
        Statement.command
          ~dialect:Dialect.portable
          Delete.(from Person.table |> all_rows |> command)
      in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql command in
      print_s (Statement.sexp_of_output inspection.output);
      [%expect {| Command_output |}]
    ;;

    let%test "optional query reports its result cardinality" =
      let statement =
        Statement.expect_optional
          ~dialect:Dialect.portable
          Query.(
            from Person.table
            |> select (fun person -> Projection.expr (Person.name person)))
      in
      let _, inspection = Statement.inspect_exn ~dialect:Sqlite statement in
      match inspection.output with
      | Statement.Query_output
          { cardinality = `Optional
          ; columns =
              [ { position = 1
                ; name = Some "name"
                ; db_type = "text"
                ; dialect_type = None
                }
              ]
          } -> true
      | Statement.Query_output _ | Statement.Command_output -> false
    ;;

    let%test "command metadata is available without input" =
      let command =
        Statement.command
          ~dialect:Dialect.portable
          Delete.(
            from Person.table |> where (fun person -> Person.id person =$ 7L) |> command)
      in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql command in
      match inspection.parameters with
      | [ { placeholder = "$1"; value = None; _ } ] -> true
      | _ -> false
    ;;

    let%test "invalid pagination input retains its name" =
      let statement =
        Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
          let%map.Statement.Parameters maximum_rows =
            params.non_negative_int ~name:"maximum_rows" ~get:Fn.id
          in
          params.query_many
            Query.(
              from Person.table
              |> limit_param maximum_rows
              |> select (fun person -> Projection.expr (Person.id person))))
      in
      match Statement.inspect ~dialect:Sqlite ~input:(-1) statement with
      | Error
          (Statement.Statement_error
             (Statement.Invalid_parameter
                { name = Some "maximum_rows"
                ; message = Statement.Negative_pagination_value -1
                })) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test_unit "getter runs once for repeated slot" =
      let calls = ref 0 in
      let statement =
        Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
          let%map.Statement.Parameters id =
            params.column Person.id_column ~get:(fun input ->
              Int.incr calls;
              input)
          in
          params.query_many
            Query.(
              from Person.table
              |> where (fun person ->
                Person.id person =. id &&. (Person.id person >=. id))
              |> select (fun person -> Projection.expr (Person.id person))))
      in
      ignore (Statement.inspect_exn ~dialect:Postgresql statement);
      assert (Int.equal !calls 0);
      ignore (Statement.inspect_exn ~dialect:Postgresql ~input:7L statement);
      assert (Int.equal !calls 1)
    ;;

    let%test "dynamic inspection requires input and evaluates once" =
      let builds = ref 0 in
      let statement =
        Statement.Dynamic.query_many ~dialect:Dialect.portable (fun id ->
          Int.incr builds;
          Query.(
            from Person.table
            |> where (fun person -> Person.id person =$ id)
            |> select (fun person -> Projection.expr (Person.id person))))
      in
      let missing_input =
        match Statement.inspect ~dialect:Postgresql statement with
        | Error (Statement.Statement_error Statement.Dynamic_input_required) -> true
        | Ok _ | Error _ -> false
      in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:7L statement in
      missing_input
      && Int.equal !builds 1
      && Int.equal (List.length inspection.parameters) 1
      &&
      match inspection.tree with
      | Statement.Leaf { kind = `Query; mode = `Dynamic } -> true
      | _ -> false
    ;;

    let%test "dynamic command inspection requires input" =
      let command =
        Statement.Dynamic.command ~dialect:Dialect.portable (fun id ->
          Delete.(
            from Person.table |> where (fun person -> Person.id person =$ id) |> command))
      in
      let missing_input =
        match Statement.inspect ~dialect:Sqlite command with
        | Error (Statement.Statement_error Statement.Dynamic_input_required) -> true
        | Ok _ | Error _ -> false
      in
      missing_input
      &&
      let _, inspection = Statement.inspect_exn ~dialect:Sqlite ~input:7L command in
      match inspection.parameters with
      | [ { value = Some (Statement.Encoded "7"); _ } ] -> true
      | _ -> false
    ;;

    let%expect_test "dynamic command has a structured tree" =
      let command =
        Statement.Dynamic.command ~dialect:Dialect.portable (fun () ->
          Delete.(from Person.table |> all_rows |> command))
      in
      let _, inspection = Statement.inspect_exn ~dialect:Sqlite ~input:() command in
      print_s (Statement.sexp_of_statement_tree inspection.tree);
      [%expect {| (Leaf (kind Command) (mode Dynamic)) |}]
    ;;

    let%test "input-selected branch is inspected once" =
      let chosen =
        Statement.choose
          ~when_:(fun input -> Option.is_some input.name)
          ~if_true:statement
          ~if_false:statement
      in
      let missing_input =
        match Statement.inspect ~dialect:Sqlite chosen with
        | Error (Statement.Statement_error Statement.Dynamic_input_required) -> true
        | Ok _ | Error _ -> false
      in
      let _, inspection = Statement.inspect_exn ~dialect:Sqlite ~input chosen in
      missing_input && Int.equal (List.length inspection.parameters) 2
    ;;

    let%test "false input branch is marked in the tree" =
      let chosen =
        Statement.choose
          ~when_:(fun input -> Option.is_some input.name)
          ~if_true:statement
          ~if_false:statement
      in
      let _, inspection =
        Statement.inspect_exn ~dialect:Sqlite ~input:{ input with name = None } chosen
      in
      match inspection.tree with
      | Statement.Input_choice
          { selected = Some false
          ; if_true = Statement.Leaf { kind = `Query; mode = `Static }
          ; if_false = Statement.Leaf { kind = `Query; mode = `Static }
          } -> true
      | _ -> false
    ;;
  end)
;;

let%test "anonymous constant keeps its value" =
  match constant_parameter ~dialect:Sqlite Db_type.text "Ada" with
  | { name = None; value = Some (Statement.Encoded "Ada"); _ } -> true
  | _ -> false
;;

let%test "computed output has no source column name" =
  let statement =
    Statement.query_one
      ~dialect:Dialect.portable
      (Query.select_one (Expr.constant Db_type.int 7))
  in
  let _, inspection = Statement.inspect_exn ~dialect:Postgresql statement in
  match inspection.output with
  | Statement.Query_output
      { cardinality = `One
      ; columns =
          [ { position = 1; name = None; db_type = "int"; dialect_type = Some "integer" }
          ]
      } -> true
  | Statement.Query_output _ | Statement.Command_output -> false
;;

let%test "anonymous constant metadata omits its value without input" =
  let statement =
    Statement.query_one
      ~dialect:Dialect.portable
      (Query.select_one (Expr.constant Db_type.text "Ada"))
  in
  let _, inspection = Statement.inspect_exn ~dialect:Postgresql statement in
  match inspection.parameters with
  | [ { value = None; db_type = "text"; _ } ] -> true
  | _ -> false
;;

let%expect_test "inspection has a structured sexp" =
  let statement =
    Statement.query_one
      ~dialect:Dialect.portable
      (Query.select_one (Expr.constant Db_type.text "Ada"))
  in
  let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:() statement in
  Statement.sexp_of_inspection inspection |> print_s;
  [%expect
    {|
    ((dialect Postgresql)
     (parameters
      (((position 1) (placeholder $1) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded Ada))))))
     (output
      (Query_output (cardinality One)
       (columns (((position 1) (name ()) (db_type text) (dialect_type (text)))))))
     (tree (Leaf (kind Query) (mode Static))))
    |}]
;;

let%expect_test "NULL diagnostic value has a structured sexp" =
  Statement.sexp_of_parameter_value Statement.Null |> print_s;
  [%expect {| Null |}]
;;

let%expect_test "statement inspection error has a structured sexp" =
  Statement.sexp_of_inspection_error
    (Statement.Statement_error Statement.Dynamic_input_required)
  |> print_s;
  [%expect {| (Statement_error Dynamic_input_required) |}]
;;

let%test "inspection exception prints its diagnostic" =
  let message =
    Stdlib.Printexc.to_string
      (Statement.Inspection_error
         (Statement.Codec_error
            { position = 1; name = Some "label"; message = "empty value" }))
  in
  String.is_substring message ~substring:"empty value"
;;

let%expect_test "many cardinality has a structured sexp" =
  Statement.sexp_of_row_cardinality `Many |> print_s;
  [%expect {| Many |}]
;;

let%expect_test "one cardinality has a structured sexp" =
  Statement.sexp_of_row_cardinality `One |> print_s;
  [%expect {| One |}]
;;

let%expect_test "optional cardinality has a structured sexp" =
  Statement.sexp_of_row_cardinality `Optional |> print_s;
  [%expect {| Optional |}]
;;

let%expect_test "query kind has a structured sexp" =
  Statement.sexp_of_statement_kind `Query |> print_s;
  [%expect {| Query |}]
;;

let%expect_test "dynamic mode has a structured sexp" =
  Statement.sexp_of_statement_mode `Dynamic |> print_s;
  [%expect {| Dynamic |}]
;;

let%expect_test "encoded diagnostic value has a structured sexp" =
  Statement.sexp_of_parameter_value (Statement.Encoded "Ada") |> print_s;
  [%expect {| (Encoded Ada) |}]
;;

let%expect_test "binding error has a structured sexp" =
  Statement.sexp_of_binding_error_message Statement.Unknown_parameter_slot |> print_s;
  [%expect {| Unknown_parameter_slot |}]
;;

let%expect_test "unsupported dialect error has a structured sexp" =
  Statement.sexp_of_sql_error (Statement.Unsupported_dialect Sqlite) |> print_s;
  [%expect {| (Unsupported_dialect Sqlite) |}]
;;

let%test "dynamic compilation failure remains structured" =
  let value = Decimal.of_string "1.25" |> Option.value_exn in
  let statement =
    Statement.Dynamic.query_one ~dialect:Dialect.portable (fun () ->
      Query.select_one (Expr.constant Db_type.numeric value))
  in
  match Statement.inspect ~dialect:Sqlite ~input:() statement with
  | Error (Statement.Statement_error (Statement.Compilation_error _)) -> true
  | Ok _ | Error _ -> false
;;

let%test "inspect_exn preserves dynamic compilation exceptions" =
  let value = Decimal.of_string "1.25" |> Option.value_exn in
  let statement =
    Statement.Dynamic.query_one ~dialect:Dialect.portable (fun () ->
      Query.select_one (Expr.constant Db_type.numeric value))
  in
  match Statement.inspect_exn ~dialect:Sqlite ~input:() statement with
  | exception Statement.Definition_error _ -> true
  | _ -> false
;;

let%test "inspect_exn raises Sql_error when dynamic input is missing" =
  let statement =
    Statement.Dynamic.query_one ~dialect:Dialect.portable (fun value ->
      Query.select_one (Expr.constant Db_type.int value))
  in
  match Statement.inspect_exn ~dialect:Postgresql statement with
  | exception Statement.Sql_error Statement.Dynamic_input_required -> true
  | _ -> false
;;

let%test "dialect-selected statements inspect their own SQL" =
  let postgresql =
    Statement.query_one
      ~dialect:Dialect.postgresql
      (Query.select_one (Expr.constant Db_type.int 1))
  in
  let sqlite =
    Statement.query_one
      ~dialect:Dialect.sqlite
      (Query.select_one (Expr.constant Db_type.int 2))
  in
  let statement = Statement.choose_dialect ~postgresql ~sqlite in
  let _, postgresql_inspection = Statement.inspect_exn ~dialect:Postgresql statement in
  let _, sqlite_inspection = Statement.inspect_exn ~dialect:Sqlite statement in
  let _, bound_sqlite_inspection =
    Statement.inspect_exn ~dialect:Sqlite ~input:() statement
  in
  match
    ( postgresql_inspection.parameters
    , sqlite_inspection.parameters
    , bound_sqlite_inspection.parameters )
  with
  | ( [ { placeholder = "$1"; _ } ]
    , [ { placeholder = "?1"; _ } ]
    , [ { value = Some (Statement.Encoded "2"); _ } ] ) -> true
  | _ -> false
;;

let%test_module "choice tree inspection" =
  (module struct
    let make_statement ~predicate_calls ~dynamic_builds =
      let postgresql =
        Statement.choose
          ~when_:(fun () ->
            Int.incr predicate_calls;
            true)
          ~if_true:
            (Statement.query_one
               ~dialect:Dialect.postgresql
               (Query.select_one (Expr.constant Db_type.int 1)))
          ~if_false:
            (Statement.Dynamic.query_one ~dialect:Dialect.postgresql (fun () ->
               Int.incr dynamic_builds;
               Query.select_one (Expr.constant Db_type.int 2)))
      in
      let sqlite =
        Statement.query_one
          ~dialect:Dialect.sqlite
          (Query.select_one (Expr.constant Db_type.int 3))
      in
      Statement.choose_dialect ~postgresql ~sqlite
    ;;

    let%expect_test "selected path keeps the unselected branch" =
      let predicate_calls = ref 0 in
      let dynamic_builds = ref 0 in
      let statement = make_statement ~predicate_calls ~dynamic_builds in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:() statement in
      print_s (Statement.sexp_of_statement_tree inspection.tree);
      [%expect
        {|
        (Dialect_choice (selected (Postgresql))
         (postgresql
          (Input_choice (selected (true)) (if_true (Leaf (kind Query) (mode Static)))
           (if_false (Leaf (kind Query) (mode Dynamic)))))
         (sqlite (Leaf (kind Query) (mode Static))))
        |}]
    ;;

    let%test "unselected input choice remains unresolved without input" =
      let predicate_calls = ref 0 in
      let dynamic_builds = ref 0 in
      let statement = make_statement ~predicate_calls ~dynamic_builds in
      let _, inspection = Statement.inspect_exn ~dialect:Sqlite statement in
      Int.equal !predicate_calls 0
      && Int.equal !dynamic_builds 0
      &&
      match inspection.tree with
      | Statement.Dialect_choice
          { selected = Some Dialect.Sqlite
          ; postgresql = Statement.Input_choice { selected = None; _ }
          ; sqlite = Statement.Leaf { kind = `Query; mode = `Static }
          } -> true
      | _ -> false
    ;;

    let%test_unit "selected predicate runs once and unselected builder stays lazy" =
      let predicate_calls = ref 0 in
      let dynamic_builds = ref 0 in
      let statement = make_statement ~predicate_calls ~dynamic_builds in
      ignore (Statement.inspect_exn ~dialect:Postgresql ~input:() statement);
      assert (Int.equal !predicate_calls 1);
      assert (Int.equal !dynamic_builds 0)
    ;;
  end)
;;

let%test_module "command choice tree inspection" =
  (module struct
    type row

    let table : row Table.t = Table.v_exn "items"

    let static_command ~dialect =
      Statement.command ~dialect Delete.(from table |> all_rows |> command)
    ;;

    let dynamic_command ~dialect =
      Statement.Dynamic.command ~dialect (fun () ->
        Delete.(from table |> all_rows |> command))
    ;;

    let%test "unselected dialect choice retains both command modes" =
      let unselected =
        Statement.choose_dialect
          ~postgresql:(static_command ~dialect:Dialect.postgresql)
          ~sqlite:(dynamic_command ~dialect:Dialect.sqlite)
      in
      let chosen =
        Statement.choose
          ~when_:(fun () -> true)
          ~if_true:(static_command ~dialect:Dialect.portable)
          ~if_false:unselected
      in
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:() chosen in
      match inspection.tree with
      | Statement.Input_choice
          { selected = Some true
          ; if_true = Statement.Leaf { kind = `Command; mode = `Static }
          ; if_false =
              Statement.Dialect_choice
                { selected = None
                ; postgresql = Statement.Leaf { kind = `Command; mode = `Static }
                ; sqlite = Statement.Leaf { kind = `Command; mode = `Dynamic }
                }
          } -> true
      | _ -> false
    ;;
  end)
;;

let%test "PostgreSQL array uses one encoded placeholder" =
  let statement =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let%map.Statement.Parameters ids =
        params.expr ~name:"ids" (Db_type.Postgresql.array_list Db_type.int64) ~get:Fn.id
      in
      params.query_one (Query.select_one ids))
  in
  let _, inspection =
    Statement.inspect_exn ~dialect:Postgresql ~input:[ 1L; 2L ] statement
  in
  match inspection.parameters with
  | [ { dialect_type = Some "bigint[]"; value = Some (Statement.Encoded value); _ } ] ->
    String.is_substring value ~substring:"1"
  | _ -> false
;;

let%test "PostgreSQL boolean is encoded as text" =
  match constant_parameter ~dialect:Postgresql Db_type.bool true with
  | { value = Some (Statement.Encoded "true"); _ } -> true
  | _ -> false
;;

let%test "SQLite boolean uses INTEGER storage" =
  match constant_parameter ~dialect:Sqlite Db_type.bool false with
  | { dialect_type = Some "INTEGER"; value = Some (Statement.Encoded "0"); _ } -> true
  | _ -> false
;;

let%test "SQLite true boolean is encoded as one" =
  match constant_parameter ~dialect:Sqlite Db_type.bool true with
  | { value = Some (Statement.Encoded "1"); _ } -> true
  | _ -> false
;;

let%test "named PostgreSQL type uses its underlying value" =
  let db_type =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "person_name")
      Db_type.text
  in
  let statement =
    Statement.query_one
      ~dialect:Dialect.postgresql
      (Query.select_one (Expr.constant db_type "Ada"))
  in
  let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:() statement in
  match inspection.parameters with
  | [ { value = Some (Statement.Encoded "Ada"); _ } ] -> true
  | _ -> false
;;

let%test "integer value is encoded" =
  match constant_parameter ~dialect:Sqlite Db_type.int 42 with
  | { dialect_type = Some "INTEGER"; value = Some (Statement.Encoded "42"); _ } -> true
  | _ -> false
;;

let%test "float value uses REAL storage" =
  match constant_parameter ~dialect:Sqlite Db_type.float 1.25 with
  | { dialect_type = Some "REAL"; value = Some (Statement.Encoded "1.25"); _ } -> true
  | _ -> false
;;

let%test "PostgreSQL numeric value is encoded" =
  let value = Decimal.of_string "1.25" |> Option.value_exn in
  let statement =
    Statement.query_one
      ~dialect:Dialect.postgresql
      (Query.select_one (Expr.constant Db_type.numeric value))
  in
  let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input:() statement in
  match inspection.parameters with
  | [ { dialect_type = Some "numeric"; value = Some (Statement.Encoded "1.25"); _ } ] ->
    true
  | _ -> false
;;

let%test "bytes value uses BLOB storage" =
  match constant_parameter ~dialect:Sqlite Db_type.bytes (Bytes.of_string "AB") with
  | { dialect_type = Some "BLOB"; value = Some (Statement.Encoded "\\x4142"); _ } -> true
  | _ -> false
;;

let%test "date value is encoded" =
  let value = Date.of_string "2026-10-04" |> Option.value_exn in
  match constant_parameter ~dialect:Sqlite Db_type.date value with
  | { value = Some (Statement.Encoded "2026-10-04"); _ } -> true
  | _ -> false
;;

let%test "timestamp value is encoded" =
  match constant_parameter ~dialect:Sqlite Db_type.timestamp Ptime.epoch with
  | { value = Some (Statement.Encoded value); _ } ->
    String.is_prefix value ~prefix:"1970-01-01T00:00:00"
  | _ -> false
;;

let%test "UUID value is encoded" =
  let value = Uuid.of_string_exn "550e8400-e29b-41d4-a716-446655440000" in
  match constant_parameter ~dialect:Sqlite Db_type.uuid value with
  | { value = Some (Statement.Encoded "550e8400-e29b-41d4-a716-446655440000"); _ } -> true
  | _ -> false
;;
