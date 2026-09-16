open! Base
open Typed_sql
open Infix

type row

let table : row Table.t = Table.v_exn "excluded"
let id = Column.v_exn table "id" Db_type.int64
let name = Column.v_exn table "name" Db_type.text
let nickname = Column.nullable_v_exn table "nickname" Db_type.text
let target = Insert.Conflict_target.(column id |> add name)

let ok result =
  result |> Result.map_error ~f:Compile_error.to_string |> Result.ok_or_failwith
;;

let compile dialect command = Compiler.compile_portable_command ~dialect command
let insert () = Insert.(into table |> set id 1L |> set name "Ada")
let update f = Insert.(insert () |> on_conflict target |> do_update f)

let%expect_test "conditional composite multi-row UPSERT and RETURNING" =
  let query =
    Insert.(
      rows
        table
        [ (fun row -> row |> set id 1L |> set name "Ada")
        ; (fun row -> row |> set name "Grace" |> set id 2L)
        ]
      |> on_conflict target
      |> do_update (fun ~existing ~excluded ->
        Conflict_update.(
          empty
          |> set_expr name (Expr.upper (Expr.column excluded name))
          |> set_opt nickname (Some None)
          |> where (Expr.column existing id >$ 0L)
          |> where (Expr.column existing name <>. Expr.column excluded name)))
      |> returning (fun row ->
        Projection.pair (Expr.column row name) (Expr.param Db_type.int 9)))
  in
  Compiler.compile ~dialect:Dialect.postgresql query
  |> ok
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "excluded" AS t0 (
      "id",
      "name"
    )
    VALUES
      ($1, $2),
      ($3, $4)
    ON CONFLICT (
      "id",
      "name"
    )
    DO UPDATE
    SET
      "name" = UPPER(excluded."name"),
      "nickname" = $5
    WHERE
      (
        (t0."id" > $6)
        AND (t0."name" <> excluded."name")
      )
    RETURNING
      "name",
      $7
    |}];
  Compiler.compile ~dialect:Dialect.sqlite query
  |> ok
  |> Compiled_query.sql
  |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "excluded" AS t0 (
      "id",
      "name"
    )
    VALUES
      (?1, ?2),
      (?3, ?4)
    ON CONFLICT (
      "id",
      "name"
    )
    DO UPDATE
    SET
      "name" = UPPER(excluded."name"),
      "nickname" = ?5
    WHERE
      (
        (t0."id" > ?6)
        AND (t0."name" <> excluded."name")
      )
    RETURNING
      "name",
      ?7
    |}]
;;

let%expect_test "target-specific DO NOTHING is portable" =
  let command = Insert.(insert () |> on_conflict target |> do_nothing |> command) in
  compile Dialect.Postgresql command |> ok |> Compiled_command.sql |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "excluded" (
      "id",
      "name"
    )
    VALUES
      ($1, $2)
    ON CONFLICT (
      "id",
      "name"
    )
    DO NOTHING
    |}];
  compile Dialect.Sqlite command |> ok |> Compiled_command.sql |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "excluded" (
      "id",
      "name"
    )
    VALUES
      (?1, ?2)
    ON CONFLICT (
      "id",
      "name"
    )
    DO NOTHING
    |}]
;;

let%test_unit "optional fields and predicates preserve immutable actions" =
  let action = Insert.Conflict_update.(empty |> set name "Ada") in
  let optional =
    Insert.Conflict_update.(
      action |> set_opt nickname None |> set_expr_opt id None |> where Condition.true_)
  in
  let changed =
    Insert.Conflict_update.(
      action
      |> set_expr_opt id (Some (Expr.param Db_type.int64 3L))
      |> where Condition.false_)
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let sql action =
      Insert.(update (fun ~existing:_ ~excluded:_ -> action) |> command)
      |> compile dialect
      |> ok
      |> Compiled_command.sql
    in
    assert (String.equal (sql action) (sql optional));
    assert (not (String.equal (sql action) (sql changed)));
    let empty =
      Insert.(
        update (fun ~existing:_ ~excluded:_ ->
          Conflict_update.(empty |> set_opt name None))
        |> command)
      |> compile dialect
    in
    match empty with
    | Error Compile_error.Empty_conflict_update -> ()
    | _ -> failwith "empty optional update was accepted")
;;

let%test_unit "conflict columns retain their owning table" =
  let other_table : row Table.t = Table.v_exn "other" in
  let other_id = Column.v_exn other_table "id" Db_type.int64 in
  let invalid_target =
    Insert.(
      insert () |> on_conflict (Conflict_target.column other_id) |> do_nothing |> command)
  in
  let invalid_assignment =
    Insert.(
      insert ()
      |> on_conflict target
      |> do_update (fun ~existing:_ ~excluded:_ ->
        Conflict_update.(empty |> set other_id 2L))
      |> command)
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    (match compile dialect invalid_target with
     | Error (Compile_error.Invalid_conflict_target_source _ as error) ->
       assert (
         String.is_prefix
           (Compile_error.to_string error)
           ~prefix:"ON CONFLICT target column belongs to source #")
     | _ -> failwith "foreign conflict target column was accepted");
    match compile dialect invalid_assignment with
    | Error (Compile_error.Invalid_assignment_source _) -> ()
    | _ -> failwith "foreign conflict assignment column was accepted")
;;

let%test_unit "escaped references cannot reach VALUES, RETURNING or other actions" =
  let existing = ref None in
  let excluded = ref None in
  let original =
    update (fun ~existing:row ~excluded:proposed ->
      existing := Some row;
      excluded := Some proposed;
      Insert.Conflict_update.(empty |> set_expr name (Expr.column proposed name)))
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    List.iter
      [ Option.value_exn !existing; Option.value_exn !excluded ]
      ~f:(fun reference ->
        let expression = Expr.column reference nickname in
        let rejected = function
          | Error (Compile_error.Foreign_source _) -> ()
          | _ -> failwith "escaped reference was accepted"
        in
        Insert.(original |> set_expr nickname expression |> command)
        |> compile dialect
        |> rejected;
        Insert.(
          update (fun ~existing:_ ~excluded:_ ->
            Conflict_update.(empty |> set_expr nickname expression))
          |> command)
        |> compile dialect
        |> rejected;
        Insert.(
          update (fun ~existing:_ ~excluded:_ ->
            Conflict_update.(empty |> set name "new" |> where (Expr.is_null expression)))
          |> command)
        |> compile dialect
        |> rejected);
    Insert.(
      original
      |> returning (fun _ ->
        Projection.expr (Expr.column (Option.value_exn !excluded) id)))
    |> Compiler.compile_portable ~dialect
    |> function
    | Error (Compile_error.Foreign_source _) -> ()
    | _ -> failwith "excluded escaped into RETURNING")
;;

let%expect_test "invalid UPSERT assignments and local aggregates" =
  let print action =
    Insert.(update action |> command) |> compile Dialect.Sqlite |> function
    | Error error -> Stdlib.print_endline (Compile_error.to_string error)
    | Ok _ -> failwith "invalid action was accepted"
  in
  print (fun ~existing:_ ~excluded:_ ->
    Insert.Conflict_update.(empty |> set name "one" |> set name "two"));
  [%expect {| column name is assigned more than once |}];
  print (fun ~existing:_ ~excluded:_ ->
    Insert.Conflict_update.(empty |> set_expr id Expr.count_all));
  [%expect {| aggregate expressions are not allowed in ON CONFLICT DO UPDATE SET |}];
  print (fun ~existing:_ ~excluded:_ ->
    Insert.Conflict_update.(empty |> set name "one" |> where (Expr.count_all >$ 0L)));
  [%expect {| aggregate expressions are not allowed in ON CONFLICT DO UPDATE WHERE |}]
;;

let%test_unit "nested aggregates and correlated predicates remain valid" =
  let builder =
    update (fun ~existing ~excluded ->
      let count =
        Query.(
          from table
          |> where (fun row -> Expr.column row name =. Expr.column existing name)
          |> select_scalar (fun _ -> Expr.count_all))
        |> Expr.scalar_subquery
      in
      let exists =
        Query.(
          from table
          |> where (fun row -> Expr.column row name =. Expr.column excluded name)
          |> exists)
      in
      Insert.Conflict_update.(
        empty
        |> set_expr name (Expr.column excluded name)
        |> where (Expr.is_null count ||. exists)))
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    ignore (Insert.(builder |> command) |> compile dialect |> ok))
;;

let%test_unit "capability traversal includes conflict assignments and WHERE" =
  let count = Column.nullable_v_exn table "count" Db_type.int64 in
  let valid =
    Query.(from table |> select_scalar (fun _ -> Expr.count_all)) |> Expr.scalar_subquery
  in
  let unsupported =
    Query.(
      from table
      |> Postgresql.Query.having (fun _ -> Expr.count_all >$ 0L)
      |> limit 1
      |> select_scalar (fun _ -> Expr.param Db_type.int64 1L))
    |> Expr.scalar_subquery
  in
  let make action = Insert.(update action |> command) in
  ignore
    (make (fun ~existing:_ ~excluded:_ ->
       Insert.Conflict_update.(empty |> set_expr count valid))
     |> compile Dialect.Sqlite
     |> ok);
  List.iter
    [ make (fun ~existing:_ ~excluded:_ ->
        Insert.Conflict_update.(empty |> set_expr count unsupported))
    ; make (fun ~existing:_ ~excluded:_ ->
        Insert.Conflict_update.(empty |> set name "x" |> where (Expr.is_null unsupported)))
    ]
    ~f:(fun command ->
      ignore (Compiler.compile_command ~dialect:Dialect.postgresql command |> ok))
;;

let%expect_test "dialect lowering applies to the conflict predicate" =
  let command =
    Insert.(
      update (fun ~existing ~excluded ->
        Conflict_update.(
          empty
          |> set_expr name (Expr.case [] ~else_:(Expr.column excluded name))
          |> where
               (Expr.is_distinct_from
                  (Expr.column existing nickname)
                  (Expr.column excluded nickname))))
      |> command)
  in
  compile Dialect.Postgresql command |> ok |> Compiled_command.sql |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "excluded" AS t0 (
      "id",
      "name"
    )
    VALUES
      ($1, $2)
    ON CONFLICT (
      "id",
      "name"
    )
    DO UPDATE
    SET
      "name" = excluded."name"
    WHERE
      (t0."nickname" IS DISTINCT FROM excluded."nickname")
    |}];
  compile Dialect.Sqlite command |> ok |> Compiled_command.sql |> Stdlib.print_endline;
  [%expect
    {|
    INSERT INTO "excluded" AS t0 (
      "id",
      "name"
    )
    VALUES
      (?1, ?2)
    ON CONFLICT (
      "id",
      "name"
    )
    DO UPDATE
    SET
      "name" = excluded."name"
    WHERE
      (t0."nickname" IS NOT excluded."nickname")
    |}]
;;
