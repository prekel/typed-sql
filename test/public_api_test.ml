open! Base
open Typed_sql
open Statement_compile
open Infix

let ok_exn result =
  Result.map_error result ~f:Compile_error.to_string |> Result.ok_or_failwith
;;

let error_exn = function
  | Error error -> error
  | Ok _ -> failwith "expected compilation error"
;;

let items : unit Table.t = Table.v_exn "items"
let id = Column.v_exn items "id" Db_type.int
let name = Column.nullable_v_exn items "name" Db_type.text
let projection row = Projection.expr (Expr.column row id)
let query () = Query.(from items)

type statement_input =
  { minimum_id : int
  ; maximum_rows : int
  ; start_at : int
  ; filtered : bool
  }

let statement_builds = ref 0

let filtered_statement =
  Statement.Portable.query_many_exn (fun params ->
    Int.incr statement_builds;
    let minimum_id =
      params.column ~name:"minimum_id" id ~get:(fun input -> input.minimum_id)
    in
    let maximum_rows =
      params.non_negative_int ~name:"maximum_rows" ~get:(fun input -> input.maximum_rows)
    in
    let start_at =
      params.non_negative_int ~name:"start_at" ~get:(fun input -> input.start_at)
    in
    Query.(
      from items
      |> where (fun row ->
        Expr.column row id >=. minimum_id &&. (Expr.column row id <=. minimum_id))
      |> limit_param maximum_rows
      |> offset_param start_at
      |> select projection))
;;

let all_statement =
  Statement.Portable.query_many_exn
    (fun (_ : (statement_input, Dialect.portable) Statement.parameters) ->
       Query.(from items |> select projection))
;;

let selected_statement =
  Statement.choose
    ~when_:(fun input -> input.filtered)
    ~if_true:filtered_statement
    ~if_false:all_statement
;;

let insert_statement =
  Statement.Portable.command_exn (fun params ->
    let inserted_id = params.expr ~name:"id" Db_type.int ~get:Fn.id in
    Insert.(into items |> set_expr id inserted_id |> command))
;;

let compile dialect query =
  Query.(select projection query) |> Compiler.compile_portable ~dialect
;;

let sql dialect query = compile dialect query |> ok_exn |> Compiled_query.sql

let equal_dialect left right =
  match left, right with
  | Dialect.Postgresql, Dialect.Postgresql | Dialect.Sqlite, Dialect.Sqlite -> true
  | _ -> false
;;

let%test_unit "statements compile once and bind one typed input" =
  assert (Int.(!statement_builds = 1));
  let input = { minimum_id = 7; maximum_rows = 10; start_at = 0; filtered = true } in
  let postgresql =
    Statement.sql_exn ~dialect:Dialect.Postgresql ~input filtered_statement
  in
  let sqlite = Statement.sql_exn ~dialect:Dialect.Sqlite ~input filtered_statement in
  let postgresql_without_input =
    Statement.sql_exn ~dialect:Dialect.Postgresql filtered_statement
  in
  let sqlite_without_input =
    Statement.sql_exn ~dialect:Dialect.Sqlite filtered_statement
  in
  assert (String.equal postgresql postgresql_without_input);
  assert (String.equal sqlite sqlite_without_input);
  assert (
    Int.(
      String.substr_index_all postgresql ~may_overlap:true ~pattern:"$1"
      |> List.length
      = 2));
  assert (Int.(String.count postgresql ~f:(Char.equal '$') = 4));
  assert (
    Int.(
      String.substr_index_all sqlite ~may_overlap:true ~pattern:"?1" |> List.length = 2));
  assert (Int.(String.count sqlite ~f:(Char.equal '?') = 4));
  ignore (Statement.sql_exn ~dialect:Dialect.Postgresql ~input filtered_statement);
  assert (Int.(!statement_builds = 1))
;;

let%test_unit "command statements bind runtime expressions" =
  let postgresql =
    Statement.sql_exn ~dialect:Dialect.Postgresql ~input:42 insert_statement
  in
  let sqlite = Statement.sql_exn ~dialect:Dialect.Sqlite ~input:42 insert_statement in
  let sqlite_without_input = Statement.sql_exn ~dialect:Dialect.Sqlite insert_statement in
  assert (String.is_substring postgresql ~substring:"$1");
  assert (String.is_substring sqlite ~substring:"?1");
  assert (String.equal sqlite sqlite_without_input)
;;

let%test_unit "rendering static SQL without input does not evaluate getters" =
  let getter_calls = ref 0 in
  let statement =
    Statement.Portable.query_many_exn (fun params ->
      let runtime_id =
        params.column id ~get:(fun input ->
          Int.incr getter_calls;
          input)
      in
      Query.(
        from items
        |> where (fun row -> Expr.column row id =. runtime_id)
        |> select projection))
  in
  let sql = Statement.sql_exn ~dialect:Dialect.Sqlite statement in
  assert (String.is_substring sql ~substring:"?1");
  assert (Int.(!getter_calls = 0));
  ignore (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:7 statement);
  assert (Int.(!getter_calls = 1))
;;

let%test_unit "runtime pagination is validated before execution" =
  let input = { minimum_id = 7; maximum_rows = -1; start_at = 0; filtered = true } in
  match Statement.sql ~dialect:Dialect.Sqlite ~input filtered_statement with
  | Error
      (Statement.Invalid_parameter
         { name = Some name; message = "must be non-negative, got -1" }) ->
    assert (String.equal name "maximum_rows")
  | Error _ | Ok _ -> failwith "negative runtime LIMIT was accepted"
;;

let%test_unit "choose selects only precompiled statement variants" =
  let input filtered = { minimum_id = 7; maximum_rows = 10; start_at = 0; filtered } in
  let filtered =
    Statement.sql_exn ~dialect:Dialect.Postgresql ~input:(input true) selected_statement
  in
  let all =
    Statement.sql_exn ~dialect:Dialect.Postgresql ~input:(input false) selected_statement
  in
  assert (String.is_substring filtered ~substring:"WHERE");
  assert (not (String.is_substring all ~substring:"WHERE"))
;;

let statement_query = Query.(from items |> select projection)

let%test_unit "dialect-specific statement constructors preserve cardinality" =
  let definition_error (error : Statement.definition_error) =
    Compile_error.to_string error.error
  in
  let one =
    Statement.For_dialect.query_one ~dialect:Dialect.postgresql (fun _ -> statement_query)
    |> Result.map_error ~f:definition_error
    |> Result.ok_or_failwith
  in
  let optional =
    Statement.For_dialect.query_optional ~dialect:Dialect.postgresql (fun _ ->
      statement_query)
    |> Result.map_error ~f:definition_error
    |> Result.ok_or_failwith
  in
  ignore (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:() one);
  ignore (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:() optional);
  ignore
    (Statement.For_dialect.query_one_exn ~dialect:Dialect.postgresql (fun _ ->
       statement_query));
  ignore
    (Statement.For_dialect.query_optional_exn ~dialect:Dialect.postgresql (fun _ ->
       statement_query))
;;

let%test_unit "statement reports unsupported runtime dialects" =
  let query =
    Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun _ ->
      statement_query)
  in
  (match Statement.sql ~dialect:Dialect.Sqlite ~input:() query with
   | Error (Statement.Unsupported_dialect Dialect.Sqlite) -> ()
   | Error _ | Ok _ -> failwith "PostgreSQL statement accepted SQLite");
  (match Statement.sql ~dialect:Dialect.Sqlite query with
   | Error (Statement.Unsupported_dialect Dialect.Sqlite) -> ()
   | Error _ | Ok _ -> failwith "inputless PostgreSQL statement accepted SQLite");
  (match Statement.sql_exn ~dialect:Dialect.Sqlite ~input:() query with
   | exception Failure _ -> ()
   | _ -> failwith "sql_exn accepted an unsupported dialect");
  let command =
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
      Insert.(into items |> set id 1 |> command))
  in
  (match Statement.sql ~dialect:Dialect.Sqlite ~input:() command with
   | Error (Statement.Unsupported_dialect Dialect.Sqlite) -> ()
   | Error _ | Ok _ -> failwith "PostgreSQL command accepted SQLite");
  match Statement.sql ~dialect:Dialect.Sqlite command with
  | Error (Statement.Unsupported_dialect Dialect.Sqlite) -> ()
  | Error _ | Ok _ -> failwith "inputless PostgreSQL command accepted SQLite"
;;

let%test_unit "statement exn constructors expose definition and binding failures" =
  (match
     Statement.Portable.query_many_exn (fun _ ->
       Query.(from items |> limit (-1) |> select projection))
   with
   | exception Statement.Definition_error { error = Compile_error.Negative_limit -1; _ }
     -> ()
   | _ -> failwith "invalid statement definition did not raise");
  let input = { minimum_id = 7; maximum_rows = -1; start_at = 0; filtered = true } in
  match Statement.sql_exn ~dialect:Dialect.Sqlite ~input filtered_statement with
  | exception Failure message ->
    assert (String.is_substring message ~substring:"maximum_rows")
  | _ -> failwith "invalid statement input did not raise"
;;

let%test_unit "identifier validation and descriptor accessors" =
  (match Identifier.of_string "" with
   | Error `Empty -> ()
   | _ -> failwith "empty identifier returned the wrong result");
  (match Identifier.of_string "bad\000name" with
   | Error `Contains_nul -> ()
   | _ -> failwith "identifier containing NUL returned the wrong result");
  List.iter [ ""; "bad\000name" ] ~f:(fun value ->
    match Identifier.of_string_exn value with
    | exception Stdlib.Invalid_argument message -> assert (not (String.is_empty message))
    | _ -> failwith "invalid identifier accepted");
  let identifier =
    Identifier.of_string "quoted\"name"
    |> Result.map_error ~f:Identifier.error_to_string
    |> Result.ok_or_failwith
  in
  assert (Identifier.equal identifier (Identifier.of_string_exn "quoted\"name"));
  let descriptor = Table.v ~schema:identifier identifier in
  assert (Identifier.equal (Table.name descriptor) identifier);
  assert (Option.equal Identifier.equal (Table.schema descriptor) (Some identifier));
  let column = Column.v descriptor identifier Db_type.int in
  let nullable = Column.nullable_v descriptor identifier Db_type.text in
  assert (Identifier.equal (Column.name column) identifier);
  assert (Identifier.equal (Table.name (Column.table column)) identifier);
  assert (String.equal (Db_type.name (Column.db_type column)) "int");
  assert (String.equal (Db_type.name (Column.base_db_type nullable)) "text");
  assert (String.equal (Db_type.name (Column.db_type nullable)) "option(text)");
  let mapped = Db_type.map Db_type.int ~encode:Result.return ~decode:Result.return in
  assert (String.equal (Db_type.name mapped) "mapped(int)");
  List.iter
    [ Db_type.name Db_type.bool, "bool"
    ; Db_type.name Db_type.int64, "int64"
    ; Db_type.name Db_type.float, "float"
    ; Db_type.name Db_type.bytes, "bytes"
    ; Db_type.name Db_type.date, "date"
    ; Db_type.name Db_type.uuid, "uuid"
    ]
    ~f:(fun (actual, expected) -> assert (String.equal actual expected))
;;

let%test_unit "all public database types participate in query shapes" =
  let check : type a. a Db_type.t -> a -> unit =
    fun db_type value ->
    let table : unit Table.t = Table.v_exn "typed_values" in
    let column = Column.v_exn table "value" db_type in
    List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
      Query.(
        from table
        |> where (fun row -> Expr.column row column =$ value)
        |> select (fun row -> Projection.expr (Expr.column row column)))
      |> Compiler.compile_portable ~dialect
      |> ok_exn
      |> ignore)
  in
  check Db_type.bool true;
  check Db_type.int 1;
  check Db_type.int64 1L;
  check Db_type.float 1.5;
  check Db_type.text "value";
  check Db_type.bytes (Bytes.of_string "value");
  let date = Date.of_ymd_exn ~year:2026 ~month:9 ~day:12 in
  assert (Date.equal date (Date.of_ptime (Date.to_ptime date)));
  assert (String.equal (Date.to_string date) "2026-09-12");
  assert (Option.equal Date.equal (Date.of_string "2026-09-12") (Some date));
  assert (Option.is_none (Date.of_string "2026-02-29"));
  assert (Option.is_none (Date.of_string "12-09-2026"));
  (match Date.of_ymd_exn ~year:2026 ~month:2 ~day:29 with
   | exception Stdlib.Invalid_argument _ -> ()
   | _ -> failwith "invalid calendar date accepted");
  let year, month, day = Date.to_ymd date in
  assert (Int.(year = 2026 && month = 9 && day = 12));
  check Db_type.date date;
  let uuid = Uuid.of_string_exn "550E8400-E29B-41D4-A716-446655440000" in
  assert (String.equal (Uuid.to_string uuid) "550e8400-e29b-41d4-a716-446655440000");
  assert (
    Option.equal
      Uuid.equal
      (Uuid.of_string "550e8400-e29b-41d4-a716-446655440000")
      (Some uuid));
  assert (Option.is_none (Uuid.of_string "not-a-uuid"));
  assert (Option.is_none (Uuid.of_string "550g8400-e29b-41d4-a716-446655440000"));
  (match Uuid.of_string_exn "not-a-uuid" with
   | exception Stdlib.Invalid_argument _ -> ()
   | _ -> failwith "invalid UUID accepted");
  check Db_type.uuid uuid;
  check (Db_type.option Db_type.text) None;
  check
    (Db_type.map
       ~name:"positive"
       ~encode:(fun value ->
         if value > 0 then
           Ok value
         else
           Error "not positive")
       ~decode:(fun value ->
         if value > 0 then
           Ok value
         else
           Error "not positive")
       Db_type.int)
    1
;;

let%expect_test "public diagnostic printers" =
  Stdlib.Format.printf "%a@." Identifier.pp (Identifier.of_string_exn "items");
  [%expect {| items |}];
  Stdlib.print_endline (Identifier.error_to_string `Empty);
  [%expect {| SQL identifier must not be empty |}];
  Stdlib.print_endline (Identifier.error_to_string `Contains_nul);
  [%expect {| SQL identifier must not contain a NUL byte |}];
  Stdlib.Format.printf "%a@." Affected_rows.pp (Affected_rows.Known 2);
  [%expect {| 2 |}];
  Stdlib.Format.printf "%a@." Affected_rows.pp Affected_rows.Unknown;
  [%expect {| unknown |}];
  Stdlib.Format.printf
    "%a@."
    Compile_error.pp
    (Compile_error.Invalid_assignment_source { expected = 1; actual = 2 });
  [%expect {| assignment belongs to source #2, but the command targets source #1 |}];
  Stdlib.Format.printf
    "%a@."
    Compile_error.pp
    (Compile_error.Foreign_source { visible = [ 1; 2 ]; actual = 3 });
  [%expect {| expression references source #3, but the visible sources are 1, 2 |}]
;;

let%test_unit "compiled SQL printers return the canonical execution text" =
  let query = query () |> compile Dialect.Postgresql |> ok_exn in
  let command =
    Insert.(into items |> set id 1 |> command)
    |> Compiler.compile_command ~dialect:Dialect.sqlite
    |> ok_exn
  in
  assert (
    String.equal
      (Compiled_query.sql query)
      (Stdlib.Format.asprintf "%a" Compiled_query.pp query));
  assert (
    String.equal
      (Compiled_command.sql command)
      (Stdlib.Format.asprintf "%a" Compiled_command.pp command))
;;

let%test_unit "condition identities preserve compiled SQL for both dialects" =
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let atom = Expr.constant Db_type.int 1 =$ 1 in
    let other = Expr.constant Db_type.int 2 <>$ 3 in
    let render predicate = sql dialect Query.(query () |> where (fun _ -> predicate)) in
    List.iter
      [ Condition.true_ &&. atom, atom
      ; atom &&. Condition.true_, atom
      ; Condition.false_ ||. atom, atom
      ; atom ||. Condition.false_, atom
      ; Condition.true_ &&. Condition.true_, Condition.true_
      ; Condition.false_ ||. Condition.false_, Condition.false_
      ; atom &&. Condition.false_, Condition.false_
      ; Condition.true_ ||. atom, Condition.true_
      ; Condition.not_ Condition.true_, Condition.false_
      ; Condition.not_ Condition.false_, Condition.true_
      ; Condition.not_ (Condition.not_ atom), atom
      ; atom &&. other &&. atom, atom &&. (other &&. atom)
      ; atom ||. other ||. atom, atom ||. (other ||. atom)
      ]
      ~f:(fun (left, right) -> assert (String.equal (render left) (render right)));
    assert (String.equal (render Condition.true_) (sql dialect (query ()))))
;;

let%expect_test "null checks, NOT, OR and multiple sort keys" =
  let query =
    Query.(
      query ()
      |> where (fun row ->
        Expr.is_null (Expr.column row name)
        ||. Condition.not_ (Expr.is_not_null (Expr.to_nullable (Expr.column row id))))
      |> where_opt (Some 0) ~f:(fun row value -> Expr.column row id >$ value)
      |> order_by (fun row -> Expr.column row name) `Asc
      |> order_by (fun row -> Expr.column row id) `Desc
      |> limit 3
      |> offset 1)
  in
  Stdlib.print_endline (sql Dialect.Postgresql query);
  [%expect
    {|
    SELECT
      t0."id"
    FROM "items" AS t0
    WHERE
      (
        (
          (t0."name" IS NULL)
          OR (NOT (t0."id" IS NOT NULL))
        )
        AND (t0."id" > $1)
      )
    ORDER BY
      t0."name" ASC,
      t0."id" DESC
    LIMIT 3
    OFFSET 1
    |}];
  Stdlib.print_endline (sql Dialect.Sqlite query);
  [%expect
    {|
    SELECT
      t0."id"
    FROM "items" AS t0
    WHERE
      (
        (
          (t0."name" IS NULL)
          OR (NOT (t0."id" IS NOT NULL))
        )
        AND (t0."id" > ?1)
      )
    ORDER BY
      t0."name" ASC,
      t0."id" DESC
    LIMIT 3
    OFFSET 1
    |}]
;;

let%test_unit "expression operators agree with bound-value operators" =
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let left = Expr.constant Db_type.int 1 in
    let right = Expr.constant Db_type.int 2 in
    let render condition = sql dialect Query.(query () |> where (fun _ -> condition)) in
    List.iter
      [ left =. right, left =$ 2
      ; left <>. right, left <>$ 2
      ; left <. right, left <$ 2
      ; left <=. right, left <=$ 2
      ; left >. right, left >$ 2
      ; left >=. right, left >=$ 2
      ; ( Expr.constant Db_type.text "a" =~. Expr.constant Db_type.text "%"
        , Expr.constant Db_type.text "a" =~$ "%" )
      ]
      ~f:(fun (a, b) -> assert (String.equal (render a) (render b))))
;;

let%test_unit "foreign sources are rejected in projection, sorting, JOIN and DML" =
  let escaped = ref None in
  let _ =
    Query.(
      from items
      |> select (fun row ->
        escaped := Some row;
        projection row))
  in
  let foreign = Option.value_exn !escaped in
  let expression = Expr.column foreign id in
  let check result =
    match error_exn result with
    | Compile_error.Foreign_source { visible; actual } ->
      assert (not (List.mem visible actual ~equal:Int.equal))
    | _ -> failwith "expected foreign source"
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    check
      (Query.(query () |> select (fun _ -> Projection.expr expression))
       |> Compiler.compile_portable ~dialect);
    List.iter
      [ Query.(query () |> order_by (fun _ -> expression) `Asc)
      ; Query.(query () |> where (fun row -> Expr.column row id =. expression))
      ; Query.(
          query ()
          |> where (fun _ -> Condition.not_ (Expr.is_null (Expr.to_nullable expression))))
      ]
      ~f:(fun query -> check (compile dialect query));
    check
      (Query.(
         query ()
         |> inner_join items ~on:(fun _ _ -> expression =$ 0)
         |> select (fun _ -> Projection.expr expression))
       |> Compiler.compile_portable ~dialect);
    check
      (Compiler.compile_portable_command
         ~dialect
         Insert.(into items |> set_expr id expression |> command));
    check
      (Compiler.compile_portable_command
         ~dialect
         Update.(table items |> set_expr id expression |> all_rows |> command));
    check
      (Compiler.compile_portable_command
         ~dialect
         Delete.(from items |> where (fun _ -> expression =$ 0) |> command));
    check
      (Compiler.compile_portable
         ~dialect
         Insert.(
           into items |> set id 1 |> returning (fun _ -> Projection.expr expression))))
;;

let%expect_test "invalid DML and pagination diagnostics" =
  let print_result result =
    Stdlib.Format.printf "%a@." Compile_error.pp (error_exn result)
  in
  print_result
    (Compiler.compile_command ~dialect:Dialect.sqlite Insert.(into items |> command));
  [%expect {| INSERT must assign at least one column |}];
  print_result
    (Compiler.compile_command
       ~dialect:Dialect.sqlite
       Update.(table items |> all_rows |> command));
  [%expect {| UPDATE must assign at least one column |}];
  print_result
    (Compiler.compile_command
       ~dialect:Dialect.sqlite
       Insert.(into items |> set id 1 |> set id 2 |> command));
  [%expect {| column id is assigned more than once |}];
  print_result
    (Compiler.compile
       ~dialect:Dialect.sqlite
       Delete.(from items |> all_rows |> returning (fun _ -> Projection.return ())));
  [%expect {| SELECT projection must contain at least one expression |}];
  print_result (compile Dialect.Sqlite Query.(query () |> offset (-1)));
  [%expect {| OFFSET must be non-negative, got -1 |}]
;;

let%expect_test "multi-assignment UPDATE and DELETE RETURNING" =
  let updated =
    Update.(
      table items
      |> set_expr id (Expr.constant Db_type.int 2)
      |> set name (Some "updated")
      |> where (fun row -> Expr.column row id >$ 0)
      |> where (fun row -> Expr.column row id <$ 3)
      |> returning projection)
  in
  let deleted =
    Delete.(
      from items
      |> where (fun row -> Expr.column row id >=$ 0)
      |> where (fun row -> Expr.column row id <=$ 3)
      |> returning projection)
  in
  let render dialect query =
    Compiler.compile_portable ~dialect query |> ok_exn |> Compiled_query.sql
  in
  Stdlib.print_endline (render Dialect.Postgresql updated);
  [%expect
    {|
    UPDATE "items"
    SET
      "id" = $1,
      "name" = $2
    WHERE
      (
        ("id" > $3)
        AND ("id" < $4)
      )
    RETURNING
      "id"
    |}];
  Stdlib.print_endline (render Dialect.Sqlite updated);
  [%expect
    {|
    UPDATE "items"
    SET
      "id" = ?1,
      "name" = ?2
    WHERE
      (
        ("id" > ?3)
        AND ("id" < ?4)
      )
    RETURNING
      "id"
    |}];
  Stdlib.print_endline (render Dialect.Postgresql deleted);
  [%expect
    {|
    DELETE FROM "items"
    WHERE
      (
        ("id" >= $1)
        AND ("id" <= $2)
      )
    RETURNING
      "id"
    |}];
  Stdlib.print_endline (render Dialect.Sqlite deleted);
  [%expect
    {|
    DELETE FROM "items"
    WHERE
      (
        ("id" >= ?1)
        AND ("id" <= ?2)
      )
    RETURNING
      "id"
    |}]
;;

let%test_unit "builders are immutable and all_rows clears filters" =
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let base = query () in
    let filtered = Query.(base |> where (fun row -> Expr.column row id =$ 1)) in
    assert (not (String.equal (sql dialect base) (sql dialect filtered)));
    let compiled = compile dialect base |> ok_exn in
    assert (equal_dialect (Compiled_query.dialect compiled) dialect);
    let render command =
      let compiled = Compiler.compile_portable_command ~dialect command |> ok_exn in
      assert (equal_dialect (Compiled_command.dialect compiled) dialect);
      Compiled_command.sql compiled
    in
    let update = Update.(table items |> set id 1) in
    assert (
      String.equal
        (render
           Update.(update |> where (fun _ -> Condition.false_) |> all_rows |> command))
        (render Update.(update |> all_rows |> command)));
    assert (
      String.equal
        (render
           Delete.(from items |> where (fun _ -> Condition.false_) |> all_rows |> command))
        (render Delete.(from items |> all_rows |> command))))
;;

let%test_unit "schema IR preserves metadata and generates public descriptors" =
  let identifier = Identifier.of_string_exn in
  let columns =
    [ Schema_ir.column
        ~name:(identifier "id")
        ~db_type:Int64
        ~nullable:false
        ~primary_key_position:1
        ()
    ; Schema_ir.column
        ~name:(identifier "display-name")
        ~db_type:Text
        ~nullable:true
        ~default:"'anonymous'"
        ()
    ; Schema_ir.column
        ~name:(identifier "created_at")
        ~db_type:Timestamp
        ~nullable:false
        ~generated:true
        ()
    ]
  in
  let foreign_key =
    Schema_ir.foreign_key
      ~columns:[ identifier "id" ]
      ~referenced_schema:(identifier "auth")
      ~referenced_table:(identifier "accounts")
      ~referenced_columns:[ identifier "id" ]
      ()
  in
  let unique =
    Schema_ir.unique_constraint
      ~name:(identifier "users_display_name_key")
      [ identifier "display-name" ]
  in
  let table =
    Schema_ir.table
      ~schema:(identifier "public")
      ~name:(identifier "users")
      ~columns
      ~foreign_keys:[ foreign_key ]
      ~unique_constraints:[ unique ]
      ()
  in
  let schema = Schema_ir.v [ table ] in
  assert (List.length (Schema_ir.tables schema) = 1);
  assert (Identifier.equal (Schema_ir.table_name table) (identifier "users"));
  assert (Option.is_some (Schema_ir.table_schema table));
  assert (List.length (Schema_ir.columns table) = 3);
  assert (List.length (Schema_ir.foreign_keys table) = 1);
  assert (List.length (Schema_ir.unique_constraints table) = 1);
  let display_name = List.nth_exn columns 1 in
  assert (
    Identifier.equal (Schema_ir.column_name display_name) (identifier "display-name"));
  (match Schema_ir.column_db_type display_name with
   | Text -> ()
   | _ -> failwith "schema column returned the wrong database type");
  assert (Schema_ir.column_nullable display_name);
  assert (Option.is_some (Schema_ir.column_default display_name));
  assert (not (Schema_ir.column_generated display_name));
  assert (Option.is_none (Schema_ir.column_primary_key_position display_name));
  assert (List.length (Schema_ir.foreign_key_columns foreign_key) = 1);
  assert (Option.is_some (Schema_ir.foreign_key_referenced_schema foreign_key));
  assert (
    Identifier.equal
      (Schema_ir.foreign_key_referenced_table foreign_key)
      (identifier "accounts"));
  assert (List.length (Schema_ir.foreign_key_referenced_columns foreign_key) = 1);
  assert (Option.is_some (Schema_ir.unique_constraint_name unique));
  assert (List.length (Schema_ir.unique_constraint_columns unique) = 1);
  let all_types =
    Schema_ir.table
      ~name:(identifier "123-order")
      ~columns:
        [ Schema_ir.column ~name:(identifier "type") ~db_type:Bool ~nullable:false ()
        ; Schema_ir.column ~name:(identifier "count") ~db_type:Int ~nullable:false ()
        ; Schema_ir.column ~name:(identifier "ratio") ~db_type:Float ~nullable:false ()
        ; Schema_ir.column ~name:(identifier "payload") ~db_type:Bytes ~nullable:false ()
        ; Schema_ir.column
            ~name:(identifier "published_on")
            ~db_type:Date
            ~nullable:false
            ()
        ; Schema_ir.column ~name:(identifier "uuid") ~db_type:Uuid ~nullable:false ()
        ]
      ()
  in
  let collision_column name =
    Schema_ir.column ~name:(identifier name) ~db_type:Text ~nullable:false ()
  in
  let colliding_table =
    Schema_ir.table
      ~name:(identifier "user-profile")
      ~columns:
        [ collision_column "id"
        ; collision_column "id-column"
        ; collision_column "display-name"
        ; collision_column "display_name"
        ; collision_column "display.name"
        ; collision_column "table"
        ]
      ()
  in
  let colliding_module =
    Schema_ir.table
      ~name:(identifier "user_profile")
      ~columns:[ collision_column "id" ]
      ()
  in
  let third_colliding_module =
    Schema_ir.table
      ~name:(identifier "USER PROFILE")
      ~columns:[ collision_column "id" ]
      ()
  in
  let generated =
    Schema_codegen.generate
      (Schema_ir.v
         [ table; all_types; colliding_table; colliding_module; third_colliding_module ])
    |> Result.map_error ~f:Schema_codegen.error_to_string
    |> Result.ok_or_failwith
  in
  assert (String.is_substring generated ~substring:"module Users = struct");
  assert (String.is_substring generated ~substring:"display_name_column");
  assert (String.is_substring generated ~substring:"Db_type.timestamp");
  assert (String.is_substring generated ~substring:"display_name_default");
  assert (String.is_substring generated ~substring:"id_primary_key_position = Some 1");
  assert (String.is_substring generated ~substring:"let foreign_keys");
  assert (String.is_substring generated ~substring:"Some \"auth\"");
  assert (String.is_substring generated ~substring:"let unique_constraints");
  assert (String.is_substring generated ~substring:"module Generated_123_order = struct");
  assert (String.is_substring generated ~substring:"type__column");
  assert (
    String.is_prefix
      generated
      ~prefix:
        "open! Base\nmodule Typed_sql_codegen = Typed_sql\nmodule Typed_sql_codegen_ptime = Ptime\n");
  assert (String.is_substring generated ~substring:"module User_profile = struct");
  assert (String.is_substring generated ~substring:"module User_profile_2 = struct");
  assert (String.is_substring generated ~substring:"module User_profile_3 = struct");
  assert (String.is_substring generated ~substring:"id_column_2_column");
  assert (String.is_substring generated ~substring:"display_name_2_column");
  assert (String.is_substring generated ~substring:"display_name_3_column");
  assert (String.is_substring generated ~substring:"table_2_column");
  let underscore =
    Schema_ir.table
      ~name:(identifier "items")
      ~columns:
        [ Schema_ir.column ~name:(identifier "_") ~db_type:Text ~nullable:false () ]
      ()
  in
  let generated_underscore =
    Schema_codegen.generate (Schema_ir.v [ underscore ])
    |> Result.map_error ~f:Schema_codegen.error_to_string
    |> Result.ok_or_failwith
  in
  assert (String.is_substring generated_underscore ~substring:"field_column");
  Parse.implementation (Lexing.from_string generated) |> ignore;
  let empty_table = Schema_ir.table ~name:(identifier "empty") ~columns:[] () in
  (match Schema_codegen.generate (Schema_ir.v [ empty_table ]) with
   | Error error ->
     assert (
       String.equal (Schema_codegen.error_to_string error) "table empty has no columns")
   | Ok _ -> failwith "empty schema table was generated");
  let unsupported =
    Schema_ir.table
      ~name:(identifier "custom")
      ~columns:
        [ Schema_ir.column
            ~name:(identifier "value")
            ~db_type:(Unsupported "jsonb")
            ~nullable:false
            ()
        ]
      ()
  in
  match Schema_codegen.generate (Schema_ir.v [ unsupported ]) with
  | Error error ->
    assert (
      String.equal
        (Schema_codegen.error_to_string error)
        "unsupported type jsonb for custom.value")
  | Ok _ -> failwith "unsupported schema type was generated"
;;
