open! Base
open Typed_sql
open Statement_compile
open Infix

module Target = struct
  type row

  let table : row Table.t = Table.v_exn "book_archive"
  let id_column = Column.v_exn table "id" Db_type.int64
  let title_column = Column.v_exn table "title" Db_type.text
  let note_column = Column.nullable_v_exn table "note" Db_type.text
  let id row = Expr.column row id_column
  let title row = Expr.column row title_column
  let projection row = Projection.pair (id row) (title row)
end

module Source = struct
  type row

  let table : row Table.t = Table.v_exn "book_import"
  let id_column = Column.v_exn table "id" Db_type.int64
  let title_column = Column.v_exn table "title" Db_type.text
  let id row = Expr.column row id_column
  let title row = Expr.column row title_column
  let projection row = Projection.pair (id row) (title row)
end

module Aggregate_source = struct
  type row

  let table : row Table.t = Table.v_exn "merge_aggregate_source"
  let id_column = Column.v_exn table "id" Db_type.int64
  let int_column = Column.v_exn table "int_value" Db_type.int
  let float_column = Column.v_exn table "float_value" Db_type.float
  let numeric_column = Column.v_exn table "numeric_value" Db_type.numeric
  let title_column = Column.v_exn table "title" Db_type.text
  let id row = Expr.column row id_column
  let int_value row = Expr.column row int_column
  let float_value row = Expr.column row float_column
  let numeric_value row = Expr.column row numeric_column
  let title row = Expr.column row title_column
end

let compile = Compiler.compile_command ~dialect:Dialect.postgresql

let compile_exn command =
  command
  |> compile
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
;;

let sql command = command |> compile_exn |> Compiled_command.sql
let print_s sexp = Stdlib.print_endline (Sexp.to_string_hum sexp)

let merge () =
  Merge.(
    into Target.table
    |> using Source.table ~f:(fun target source merge ->
      merge
      |> on (Target.id target =. Source.id source)
      |> when_matched_update
           Assignments.(empty |> set_expr Target.title_column (Source.title source))
      |> when_not_matched_insert
           Assignments.(
             empty
             |> set_expr Target.id_column (Source.id source)
             |> set_expr Target.title_column (Source.title source))))
;;

let source_relation =
  Derived_table.create
    ~table:Source.table
    ~columns:Source.projection
    Query.(from Source.table |> select Source.projection)
;;

let%test_module "MERGE rendering" =
  (module struct
    let%expect_test "table source updates matched and inserts missing rows" =
      Merge.(merge () |> command) |> sql |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING "book_import" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          UPDATE SET
            "title" = t1."title"
        WHEN NOT MATCHED THEN
          INSERT ("id",
            "title")
          VALUES (t1."id", t1."title")
        |}]
    ;;

    let%expect_test "conditional branches preserve action and call order" =
      Merge.(
        into Target.table
        |> using Source.table ~f:(fun target source merge ->
          merge
          |> on (Target.id target =. Source.id source)
          |> when_matched_delete ~condition:(Source.title source =$ "deleted")
          |> when_not_matched_insert
               ~condition:(Source.id source >$ 0L)
               Assignments.(
                 empty
                 |> set_expr Target.id_column (Source.id source)
                 |> set_expr Target.title_column (Source.title source))
          |> when_matched_update
               ~condition:(Target.title target <>. Source.title source)
               Assignments.(empty |> set_expr Target.title_column (Source.title source))
          |> when_matched_do_nothing
          |> when_not_matched_do_nothing)
        |> command)
      |> sql
      |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING "book_import" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED AND (t1."title" = $1) THEN
          DELETE
        WHEN NOT MATCHED AND (t1."id" > $2) THEN
          INSERT ("id",
            "title")
          VALUES (t1."id", t1."title")
        WHEN MATCHED AND (t0."title" <> t1."title") THEN
          UPDATE SET
            "title" = t1."title"
        WHEN MATCHED THEN
          DO NOTHING
        WHEN NOT MATCHED THEN
          DO NOTHING
        |}]
    ;;

    let%expect_test "self MERGE assigns distinct aliases to its references" =
      Merge.(
        into Target.table
        |> using Target.table ~f:(fun target source merge ->
          merge
          |> on (Target.id target =. Target.id source)
          |> when_matched_update
               Assignments.(empty |> set_expr Target.title_column (Target.title source)))
        |> command)
      |> sql
      |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING "book_archive" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          UPDATE SET
            "title" = t1."title"
        |}]
    ;;

    let%expect_test "DEFAULT and nullable assignments remain branch values" =
      Merge.(
        into Target.table
        |> using Source.table ~f:(fun target source merge ->
          merge
          |> on (Target.id target =. Source.id source)
          |> when_matched_update
               Assignments.(
                 empty |> default Target.title_column |> set Target.note_column None)
          |> when_not_matched_insert Assignments.(empty |> default Target.id_column))
        |> command)
      |> sql
      |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING "book_import" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          UPDATE SET
            "title" = DEFAULT,
            "note" = $1
        WHEN NOT MATCHED THEN
          INSERT ("id")
          VALUES (DEFAULT)
        |}]
    ;;

    let%expect_test "RETURNING sees both target and source" =
      Merge.(
        merge ()
        |> returning (fun target source ->
          Projection.pair (Target.id target) (Source.title source)))
      |> Compiler.compile ~dialect:Dialect.postgresql
      |> Result.map_error ~f:Compile_error.to_string
      |> Result.ok_or_failwith
      |> Compiled_query.sql
      |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING "book_import" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          UPDATE SET
            "title" = t1."title"
        WHEN NOT MATCHED THEN
          INSERT ("id",
            "title")
          VALUES (t1."id", t1."title")
        RETURNING
          t0."id",
          t1."title"
        |}]
    ;;

    let%test "identifiers are escaped and branch target columns are unqualified" =
      let table : Target.row Table.t = Table.v_exn "merge\"target" in
      let column = Column.v_exn table "value\"column" Db_type.text in
      let command =
        Merge.(
          into table
          |> using Source.table ~f:(fun _ _ merge ->
            merge
            |> on Condition.true_
            |> when_matched_update Assignments.(empty |> set column "'user value'"))
          |> command)
      in
      let rendered = sql command in
      String.is_substring rendered ~substring:"\"merge\"\"target\" AS t0"
      && String.is_substring rendered ~substring:"\"value\"\"column\" = $1"
      && not (String.is_substring rendered ~substring:"'user value'")
    ;;
  end)
;;

let%test_module "MERGE relation sources" =
  (module struct
    let%expect_test "descriptor-derived source retains named columns" =
      Merge.(
        into Target.table
        |> using_derived source_relation ~f:(fun target source merge ->
          merge
          |> on (Target.id target =. Source.id source)
          |> when_matched_update
               Assignments.(empty |> set_expr Target.title_column (Source.title source)))
        |> command)
      |> sql
      |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING (
          SELECT
            t2."id" AS "id",
            t2."title" AS "title"
          FROM "book_import" AS t2
        ) AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          UPDATE SET
            "title" = t1."title"
        |}]
    ;;

    let%expect_test "inferred source exposes typed fields" =
      let relation =
        Query.(
          from Source.table
          |> select_relation (fun source ->
            Derived_table.Fields.pair (Source.id source) (Source.title source)))
      in
      Merge.(
        into Target.table
        |> using_relation relation ~f:(fun target (id, title) merge ->
          merge
          |> on (Target.id target =. id)
          |> when_matched_update Assignments.(empty |> set_expr Target.title_column title))
        |> command)
      |> sql
      |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING (
          SELECT
            t2."id" AS "field_1",
            t2."title" AS "field_2"
          FROM "book_import" AS t2
        ) AS t1
        ON (t0."id" = t1."field_1")
        WHEN MATCHED THEN
          UPDATE SET
            "title" = t1."field_2"
        |}]
    ;;

    let%expect_test "VALUES cells precede ON and branch bind parameters" =
      let values =
        Values.create
          ~table:Source.table
          ~columns:Source.projection
          ~first:
            (Values.Row.pair
               (Expr.constant Db_type.int64 1L)
               (Expr.constant Db_type.text "imported"))
          ~rest:[]
      in
      Merge.(
        into Target.table
        |> using_values values ~f:(fun target source merge ->
          merge
          |> on (Target.id target =. Source.id source &&. (Source.id source >$ 2L))
          |> when_matched_update
               ~condition:(Source.title source <>$ "ignored")
               Assignments.(empty |> set Target.title_column "updated"))
        |> command)
      |> sql
      |> Stdlib.print_endline;
      [%expect
        {|
        MERGE INTO "book_archive" AS t0
        USING (SELECT
          "v"."column1" AS "id",
          "v"."column2" AS "title"
        FROM (VALUES
          (
            $1,
            $2
          )
        ) AS "v") AS t1
        ON (
            (t0."id" = t1."id")
            AND (t1."id" > $3)
          )
        WHEN MATCHED AND (t1."title" <> $4) THEN
          UPDATE SET
            "title" = $5
        |}]
    ;;

    let%test "derived source database types are still checked" =
      let malformed =
        Derived_table.create
          ~table:Source.table
          ~columns:Source.projection
          Query.(
            from Source.table
            |> select (fun source ->
              Projection.pair (Source.title source) (Source.id source)))
      in
      let command =
        Merge.(
          into Target.table
          |> using_derived malformed ~f:(fun _ _ merge ->
            merge |> on Condition.true_ |> when_matched_do_nothing)
          |> command)
      in
      match compile command with
      | Error (Compile_error.Mismatched_relation_projection _) -> true
      | Ok _ | Error _ -> false
    ;;
  end)
;;

let%test_module "MERGE branch validation" =
  (module struct
    let branch action =
      Merge.(
        into Target.table
        |> using Source.table ~f:(fun target source merge ->
          merge |> on (Target.id target =. Source.id source) |> action target source)
        |> command)
    ;;

    let compile_message command =
      command |> compile |> Result.map_error ~f:Compile_error.to_string
    ;;

    let%test "MERGE requires at least one branch" =
      match compile_message (branch (fun _ _ merge -> merge)) with
      | Error message ->
        String.equal message "MERGE must contain at least one WHEN branch"
      | Ok _ -> false
    ;;

    let%test "UPDATE branch requires an assignment" =
      match
        compile_message
          (branch (fun _ _ -> Merge.when_matched_update Merge.Assignments.empty))
      with
      | Error message ->
        String.equal message "MERGE branch 1 UPDATE must assign at least one column"
      | Ok _ -> false
    ;;

    let%test "INSERT branch requires an assignment" =
      match
        compile_message
          (branch (fun _ _ -> Merge.when_not_matched_insert Merge.Assignments.empty))
      with
      | Error message ->
        String.equal message "MERGE branch 1 INSERT must assign at least one column"
      | Ok _ -> false
    ;;

    let%test "UPDATE branch rejects duplicate columns" =
      let command =
        branch (fun _ _ ->
          Merge.when_matched_update
            Merge.Assignments.(
              empty |> set Target.title_column "a" |> set Target.title_column "b"))
      in
      match compile command with
      | Error (Compile_error.Duplicate_assignment column) ->
        String.equal (Identifier.to_string column) "title"
      | Ok _ | Error _ -> false
    ;;

    let%test "INSERT branch rejects duplicate columns" =
      let command =
        branch (fun _ _ ->
          Merge.when_not_matched_insert
            Merge.Assignments.(
              empty |> set Target.id_column 1L |> default Target.id_column))
      in
      match compile command with
      | Error (Compile_error.Duplicate_assignment column) ->
        String.equal (Identifier.to_string column) "id"
      | Ok _ | Error _ -> false
    ;;

    let%test "assignment descriptors must belong to the target table" =
      let other : Target.row Table.t = Table.v_exn "other_archive" in
      let other_title = Column.v_exn other "title" Db_type.text in
      match
        compile
          (branch (fun _ _ ->
             Merge.when_matched_update
               Merge.Assignments.(empty |> set other_title "foreign")))
      with
      | Error (Compile_error.Invalid_assignment_source _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "unconditional matched action closes only its branch kind" =
      let command =
        branch (fun _ _ merge ->
          Merge.(
            merge
            |> when_matched_do_nothing
            |> when_not_matched_do_nothing
            |> when_matched_delete ~condition:Condition.false_))
      in
      match compile_message command with
      | Error message ->
        String.equal
          message
          "MERGE branch 3 WHEN MATCHED is unreachable after an unconditional branch of the same kind"
      | Ok _ -> false
    ;;

    let%test "unconditional missing action closes only its branch kind" =
      let command =
        branch (fun _ _ merge ->
          Merge.(
            merge
            |> when_not_matched_do_nothing
            |> when_matched_do_nothing
            |> when_not_matched_insert Assignments.(empty |> set Target.id_column 1L)))
      in
      match compile_message command with
      | Error message ->
        String.equal
          message
          "MERGE branch 3 WHEN NOT MATCHED is unreachable after an unconditional branch of the same kind"
      | Ok _ -> false
    ;;

    let%test "an explicit TRUE branch condition remains syntactically conditional" =
      let command =
        branch (fun _ _ merge ->
          Merge.(
            merge
            |> when_matched_do_nothing ~condition:Condition.true_
            |> when_matched_delete))
      in
      String.is_substring (sql command) ~substring:"WHEN MATCHED AND TRUE"
    ;;

    let%test "NOT MATCHED conditions cannot read the target" =
      let command =
        branch (fun target _ ->
          Merge.when_not_matched_do_nothing ~condition:(Target.id target >$ 0L))
      in
      match compile command with
      | Error (Compile_error.Foreign_source _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "NOT MATCHED values cannot read the target" =
      let command =
        branch (fun target _ ->
          Merge.when_not_matched_insert
            Merge.Assignments.(empty |> set_expr Target.id_column (Target.id target)))
      in
      match compile command with
      | Error (Compile_error.Foreign_source _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "NOT MATCHED scalar subqueries cannot capture the target" =
      let command =
        branch (fun target _ ->
          let query =
            Query.(
              from Source.table
              |> where (fun source -> Source.id source =. Target.id target)
              |> limit_one
              |> select_scalar Source.id)
          in
          Merge.when_not_matched_do_nothing
            ~condition:(Expr.is_not_null (Expr.scalar_subquery query)))
      in
      match compile command with
      | Error (Compile_error.Foreign_source _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "independent scalar subqueries are allowed in INSERT values" =
      let command =
        branch (fun _ _ ->
          Merge.when_not_matched_insert
            Merge.Assignments.(
              empty
              |> set_expr
                   Target.note_column
                   (Expr.scalar_subquery
                      Query.(
                        from Source.table
                        |> limit_one
                        |> select_scalar (fun _ -> Expr.constant Db_type.text "note")))))
      in
      Result.is_ok (compile command)
    ;;

    let%test "MERGE source cannot be correlated with its target" =
      let base = Merge.into Target.table in
      let captured = ref None in
      ignore
        Merge.(
          base
          |> using Source.table ~f:(fun target _ merge ->
            captured := Some target;
            merge |> on Condition.true_ |> when_matched_do_nothing));
      let target = Option.value_exn !captured in
      let relation =
        Derived_table.create
          ~table:Source.table
          ~columns:Source.projection
          Query.(
            from Source.table
            |> where (fun source -> Source.id source =. Target.id target)
            |> select Source.projection)
      in
      let command =
        Merge.(
          base
          |> using_derived relation ~f:(fun _ _ merge ->
            merge |> on Condition.true_ |> when_matched_do_nothing)
          |> command)
      in
      match compile command with
      | Error (Compile_error.Foreign_source _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "ON rejects a reference escaped from another query" =
      let escaped = ref None in
      ignore
        Query.(
          from Source.table
          |> select (fun source ->
            escaped := Some source;
            Source.projection source));
      let command =
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun target _ merge ->
            merge
            |> on (Target.id target =. Source.id (Option.value_exn !escaped))
            |> when_matched_do_nothing)
          |> command)
      in
      match compile command with
      | Error (Compile_error.Foreign_source _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "aggregate predicates cannot occur in MERGE ON" =
      let command =
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun _ source merge ->
            merge |> on (Expr.count (Source.id source) >$ 0L) |> when_matched_do_nothing)
          |> command)
      in
      Result.is_error (compile command)
    ;;

    let promoted target =
      Query.(
        from Source.table
        |> limit_one
        |> select_scalar (fun _ -> Expr.max Db_type.Orderable.int64 (Target.id target)))
      |> Expr.scalar_subquery_nullable
    ;;

    let%test "ON cannot hide an outer aggregate inside a scalar subquery" =
      let command =
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun target _ merge ->
            merge |> on (Expr.is_not_null (promoted target)) |> when_matched_do_nothing)
          |> command)
      in
      match compile command with
      | Error (Compile_error.Aggregate_not_allowed _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "WHEN cannot hide an outer aggregate inside a scalar subquery" =
      let command =
        branch (fun target _ ->
          Merge.when_matched_do_nothing ~condition:(Expr.is_not_null (promoted target)))
      in
      match compile command with
      | Error (Compile_error.Aggregate_not_allowed _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "assignment cannot hide an outer aggregate inside a scalar subquery" =
      let command =
        branch (fun target _ ->
          let title =
            Query.(
              from Source.table
              |> limit_one
              |> select_scalar (fun _ ->
                Expr.max Db_type.Orderable.text (Target.title target)))
            |> Expr.scalar_subquery_nullable
          in
          Merge.when_matched_update
            Merge.Assignments.(empty |> set_expr Target.note_column title))
      in
      match compile command with
      | Error (Compile_error.Aggregate_not_allowed _) -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "UPDATE assignment rejects a direct aggregate" =
      let command =
        branch (fun _ source ->
          let maximum = Expr.max Db_type.Orderable.int64 (Source.id source) in
          let value = Expr.coalesce maximum ~default:(Expr.constant Db_type.int64 0L) in
          Merge.when_matched_update
            Merge.Assignments.(empty |> set_expr Target.id_column value))
      in
      match compile_message command with
      | Error message ->
        String.equal message "aggregate expressions are not allowed in MERGE assignment"
      | Ok _ -> false
    ;;

    let%test "WHEN condition rejects a direct aggregate" =
      let command =
        branch (fun _ source ->
          Merge.when_matched_do_nothing
            ~condition:
              (Expr.is_not_null (Expr.max Db_type.Orderable.int64 (Source.id source))))
      in
      match compile_message command with
      | Error message ->
        String.equal message "aggregate expressions are not allowed in MERGE WHEN"
      | Ok _ -> false
    ;;

    let%test "NOT MATCHED condition rejects a correlated outer aggregate" =
      let command =
        branch (fun _ source ->
          let maximum =
            Query.(
              from Source.table
              |> limit_one
              |> select_scalar (fun _ ->
                Expr.max Db_type.Orderable.int64 (Source.id source)))
            |> Expr.scalar_subquery_nullable
          in
          Merge.when_not_matched_do_nothing ~condition:(Expr.is_not_null maximum))
      in
      match compile_message command with
      | Error message ->
        String.equal message "aggregate expressions are not allowed in MERGE WHEN"
      | Ok _ -> false
    ;;

    let%test "INSERT assignment rejects a correlated outer aggregate" =
      let command =
        branch (fun _ source ->
          let maximum =
            Query.(
              from Source.table
              |> limit_one
              |> select_scalar (fun _ ->
                Expr.max Db_type.Orderable.int64 (Source.id source)))
            |> Expr.scalar_subquery_nullable
          in
          let value = Expr.coalesce maximum ~default:(Expr.constant Db_type.int64 0L) in
          Merge.when_not_matched_insert
            Merge.Assignments.(empty |> set_expr Target.id_column value))
      in
      match compile_message command with
      | Error message ->
        String.equal message "aggregate expressions are not allowed in MERGE INSERT"
      | Ok _ -> false
    ;;

    let%test "RETURNING rejects a correlated outer aggregate" =
      let returning =
        Merge.(merge () |> returning (fun target _ -> Projection.expr (promoted target)))
      in
      match Compiler.compile ~dialect:Dialect.postgresql returning with
      | Error error ->
        String.equal
          (Compile_error.to_string error)
          "aggregate expressions are not allowed in MERGE RETURNING"
      | Ok _ -> false
    ;;

    let rejects_hidden_condition make_condition =
      let command =
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun target source merge ->
            merge |> on (make_condition target source) |> when_matched_do_nothing)
          |> command)
      in
      match compile command with
      | Error (Compile_error.Aggregate_not_allowed "MERGE ON") -> true
      | Ok _ | Error _ -> false
    ;;

    let hidden_value target =
      Expr.coalesce (promoted target) ~default:(Expr.constant Db_type.int64 0L)
    ;;

    let%test "ON rejects an outer aggregate on the left of a comparison" =
      rejects_hidden_condition (fun target source ->
        hidden_value target =. Source.id source)
    ;;

    let%test "ON rejects an outer aggregate in the subject of IN" =
      rejects_hidden_condition (fun target _ -> Expr.in_ (hidden_value target) [ 1L ])
    ;;

    let%test "ON rejects an outer aggregate in the subject of BETWEEN" =
      rejects_hidden_condition (fun target _ ->
        Expr.between (hidden_value target) ~lower:0L ~upper:10L)
    ;;

    let%test "ON rejects an outer aggregate in the lower bound of BETWEEN" =
      rejects_hidden_condition (fun target source ->
        Expr.between_exprs
          (Source.id source)
          ~lower:(hidden_value target)
          ~upper:(Expr.constant Db_type.int64 10L))
    ;;

    let%test "ON rejects an outer aggregate in the subject of IN SELECT" =
      rejects_hidden_condition (fun target _ ->
        Query.in_subquery
          (hidden_value target)
          Query.(from Source.table |> select_scalar Source.id))
    ;;

    let%test "ON rejects an outer aggregate in the ELSE value of CASE" =
      rejects_hidden_condition (fun target source ->
        Expr.case
          [ Source.id source >$ 0L, Expr.constant Db_type.int64 1L ]
          ~else_:(hidden_value target)
        >$ 0L)
    ;;

    let%test "ON rejects an outer aggregate in a CASE condition" =
      rejects_hidden_condition (fun target _ ->
        Expr.case
          [ Expr.is_not_null (promoted target), Expr.constant Db_type.int64 1L ]
          ~else_:(Expr.constant Db_type.int64 0L)
        >$ 0L)
    ;;

    let%test "RETURNING rejects a direct aggregate" =
      let returning =
        Merge.(
          merge ()
          |> returning (fun target _ -> Projection.expr (Expr.count (Target.id target))))
      in
      match Compiler.compile ~dialect:Dialect.postgresql returning with
      | Error (Compile_error.Aggregate_not_allowed "MERGE RETURNING") -> true
      | Ok _ | Error _ -> false
    ;;

    let rejects_hidden_returning make_projection =
      let returning = Merge.(merge () |> returning make_projection) in
      match Compiler.compile ~dialect:Dialect.postgresql returning with
      | Error (Compile_error.Aggregate_not_allowed "MERGE RETURNING") -> true
      | Ok _ | Error _ -> false
    ;;

    let promoted_title target =
      Query.(
        from Source.table
        |> limit_one
        |> select_scalar (fun _ -> Expr.max Db_type.Orderable.text (Target.title target)))
      |> Expr.scalar_subquery_nullable
    ;;

    let%test "local string aggregation cannot hide a MERGE aggregate in its value" =
      rejects_hidden_returning (fun target _ ->
        let scalar =
          Query.(
            from Source.table
            |> select_scalar (fun inner ->
              Postgresql.string_agg_nullable
                ~order_by:[ Aggregate_order.asc (Source.id inner) ]
                ~delimiter:(Expr.constant Db_type.text ",")
                (promoted_title target)))
        in
        Projection.expr (Expr.scalar_subquery scalar))
    ;;

    let%test "local string aggregation cannot hide a MERGE aggregate in its delimiter" =
      rejects_hidden_returning (fun target _ ->
        let scalar =
          Query.(
            from Source.table
            |> select_scalar (fun inner ->
              Postgresql.string_agg
                ~delimiter:
                  (Expr.coalesce
                     (promoted_title target)
                     ~default:(Expr.constant Db_type.text ","))
                (Source.title inner)))
        in
        Projection.expr (Expr.scalar_subquery scalar))
    ;;

    let%test "local multiset aggregation cannot hide a MERGE aggregate in its fields" =
      rejects_hidden_returning (fun target _ ->
        Query.multiset
          Query.(
            from Source.table
            |> select (fun inner ->
              Projection.multiset_agg
                (Projection.pair (Source.id inner) (promoted target)))))
    ;;

    let%test "local multiset aggregation cannot hide a MERGE aggregate in its ordering" =
      rejects_hidden_returning (fun target _ ->
        Query.multiset
          Query.(
            from Source.table
            |> select (fun inner ->
              Projection.multiset_agg
                ~order_by:[ Aggregate_order.asc (promoted target) ]
                (Projection.expr (Source.id inner)))))
    ;;

    let%test "scalar subqueries may aggregate their own local source" =
      let command =
        branch (fun _ _ ->
          let maximum =
            Query.(
              from Source.table
              |> select_scalar (fun source ->
                Expr.max Db_type.Orderable.int64 (Source.id source)))
            |> Expr.scalar_subquery_nullable
          in
          Merge.when_matched_do_nothing ~condition:(Expr.is_not_null maximum))
      in
      Result.is_ok (compile command)
    ;;

    let%test "a local aggregate may combine its own source with an outer value" =
      let command =
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun target source merge ->
            let maximum =
              Query.(
                from Source.table
                |> select_scalar (fun inner ->
                  let open Expr.Int64.Infix in
                  Expr.max Db_type.Orderable.int64 (Source.id inner +. Target.id target)))
              |> Expr.scalar_subquery_nullable
            in
            merge
            |> on (Target.id target =. Source.id source)
            |> when_matched_do_nothing ~condition:(Expr.is_not_null maximum))
          |> command)
      in
      Result.is_ok (compile command)
    ;;

    let%test "MERGE RETURNING keeps nested aggregate scopes and query forms" =
      let aggregated =
        Query.(
          from Aggregate_source.table
          |> inner_join Aggregate_source.table ~on:(fun left right ->
            Aggregate_source.id left =. Aggregate_source.id right)
          |> cross_join Aggregate_source.table
          |> where (fun ((left, right), _) ->
            let id = Aggregate_source.id left in
            let scalar =
              Query.(
                from Aggregate_source.table
                |> limit_one
                |> select_scalar Aggregate_source.id)
            in
            let correlated_exists =
              Query.(
                from Aggregate_source.table
                |> where (fun inner -> Aggregate_source.id inner =. id))
            in
            let any_ids =
              Expr.constant (Db_type.Postgresql.array_list Db_type.int64) [ 1L; 2L ]
            in
            id
            >$ 0L
            ||. (id <$ 100L)
            &&. Expr.in_ id [ 1L; 2L ]
            &&. Expr.not_in id [ 99L ]
            &&. Expr.in_exprs id [ Expr.constant Db_type.int64 3L ]
            &&. Expr.not_in_exprs id [ Expr.constant Db_type.int64 4L ]
            &&. Expr.between id ~lower:0L ~upper:100L
            &&. Postgresql.Expr.equals_any_list id any_ids
            &&. Query.in_subquery id scalar
            &&. Query.not_in_subquery id scalar
            &&. Expr.is_null (Expr.scalar_subquery scalar)
            &&. Query.exists correlated_exists
            &&. Query.not_exists correlated_exists
            &&. Condition.not_ (id =. Expr.constant Db_type.int64 (-1L))
            &&. Query.exists
                  Query.(from Aggregate_source.table |> where (fun _ -> Condition.false_))
            &&. (Aggregate_source.id right =. Aggregate_source.id left))
          |> group_by (fun ((left, _), _) -> Aggregate_source.id left)
          |> group_by (fun ((_, right), _) -> Aggregate_source.title right)
          |> having (fun ((left, _), _) -> Expr.count (Aggregate_source.id left) >$ 0L)
          |> order_by (fun ((left, _), _) -> Aggregate_source.id left) `Asc
          |> select (fun ((left, right), extra) ->
            let id = Aggregate_source.id left in
            let title = Aggregate_source.title right in
            let maximum = Expr.max Db_type.Orderable.int64 id in
            let nested_maximum =
              Query.(
                from Aggregate_source.table
                |> select_scalar (fun inner ->
                  Expr.max Db_type.Orderable.int64 (Aggregate_source.id inner)))
              |> Expr.scalar_subquery_nullable
            in
            let total =
              let open Expr.Int64.Infix in
              Expr.coalesce maximum ~default:(Expr.constant Db_type.int64 0L)
              +. Expr.count (Aggregate_source.id extra)
            in
            let text_length =
              Expr.concat (Expr.lower title) (Expr.upper title)
              |> Expr.length
              |> Expr.cast_int_to_int64
            in
            let result =
              Expr.case
                [ Expr.is_not_null maximum, total
                ; Expr.is_not_null nested_maximum, text_length
                ]
                ~else_:(Expr.constant Db_type.int64 0L)
            in
            let aggregate_values =
              Projection.both
                (Projection.both
                   (Projection.pair
                      Expr.count_all
                      (Expr.count (Aggregate_source.id left)))
                   (Projection.pair
                      (Expr.count_distinct (Aggregate_source.id right))
                      (Expr.sum_int (Aggregate_source.int_value left))))
                (Projection.both
                   (Projection.pair
                      (Expr.sum_float (Aggregate_source.float_value right))
                      (Expr.avg_float (Aggregate_source.float_value extra)))
                   (Projection.pair
                      (Expr.min Db_type.Orderable.int64 (Aggregate_source.id extra))
                      result))
            in
            let string_aggregate =
              Postgresql.string_agg
                ~delimiter:(Expr.constant Db_type.text ",")
                ~order_by:[ Aggregate_order.asc (Aggregate_source.id left) ]
                title
            in
            let multiset_aggregate =
              Projection.multiset_agg
                ~filter:(Aggregate_source.id right >$ 0L)
                ~order_by:[ Aggregate_order.desc (Aggregate_source.id extra) ]
                (Projection.pair
                   (Aggregate_source.id right)
                   (Aggregate_source.title extra))
            in
            let exists_expression =
              Query.exists_expr
                Query.(
                  from Aggregate_source.table
                  |> where (fun inner -> Aggregate_source.id inner =. id))
            in
            Projection.both
              aggregate_values
              (Projection.both
                 (Projection.both (Projection.expr string_aggregate) multiset_aggregate)
                 (Projection.expr exists_expression))))
      in
      let source_free =
        Query.multiset (Query.select_one (Expr.constant Db_type.int64 1L))
      in
      let first = Query.select_one (Expr.constant Db_type.int64 2L) in
      let second = Query.select_one (Expr.constant Db_type.int64 3L) in
      let compound = Query.multiset (Query.union first second) in
      let int64_sum =
        Query.(
          from Aggregate_source.table
          |> select_scalar (fun row ->
            Postgresql.Numeric.sum_int64 (Aggregate_source.id row)))
        |> Expr.scalar_subquery_nullable
      in
      let numeric_sum =
        Query.(
          from Aggregate_source.table
          |> select_scalar (fun row ->
            Postgresql.Numeric.sum_numeric (Aggregate_source.numeric_value row)))
        |> Expr.scalar_subquery_nullable
      in
      let numeric_average =
        Query.(
          from Aggregate_source.table
          |> select_scalar (fun row ->
            Postgresql.Numeric.avg_numeric (Aggregate_source.numeric_value row)))
        |> Expr.scalar_subquery_nullable
      in
      let returning =
        Merge.(
          merge ()
          |> returning (fun _ _ ->
            Projection.both
              (Projection.both
                 (Query.multiset aggregated)
                 (Projection.both source_free compound))
              (Projection.both
                 (Projection.expr int64_sum)
                 (Projection.both
                    (Projection.expr numeric_sum)
                    (Projection.both
                       (Projection.expr numeric_average)
                       (Projection.expr Expr.current_timestamp))))))
      in
      Result.is_ok (Compiler.compile ~dialect:Dialect.postgresql returning)
    ;;
  end)
;;

let%test_module "MERGE CTE placement" =
  (module struct
    let selected = Cte.select source_relation

    let%expect_test "a SELECT CTE supplies the USING relation" =
      Cte.with_command selected ~f:(fun source ->
        Merge.(
          into Target.table
          |> using_cte source ~f:(fun target source merge ->
            merge |> on (Target.id target =. Source.id source) |> when_matched_do_nothing)
          |> command))
      |> sql
      |> Stdlib.print_endline;
      [%expect
        {|
        WITH
          "c0" (
            "id",
            "title"
          ) AS (
            SELECT
              t0."id",
              t0."title"
            FROM "book_import" AS t0
          )
        MERGE INTO "book_archive" AS t0
        USING "c0" AS t1
        ON (t0."id" = t1."id")
        WHEN MATCHED THEN
          DO NOTHING
        |}]
    ;;

    let%test "inferred recursive CTE fields supply a MERGE CTE under a SELECT" =
      let anchor =
        Query.(
          from Source.table
          |> select_relation (fun source ->
            Derived_table.Fields.pair (Source.id source) (Source.title source)))
      in
      let definition =
        Cte.recursive_relation ~union:`Union_all ~anchor ~step:(fun source ->
          Query.(
            from_cte_relation source
            |> where (fun (id, _) -> id <$ 3L)
            |> select_relation (fun (id, title) ->
              let open Expr.Int64.Infix in
              Derived_table.Fields.pair (id +. Expr.constant Db_type.int64 1L) title)))
      in
      let query =
        Cte.with_result definition ~f:(fun source ->
          let command =
            Merge.(
              into Target.table
              |> using_cte_relation source ~f:(fun target (id, title) merge ->
                merge
                |> on (Target.id target =. id)
                |> when_matched_update
                     Assignments.(empty |> set_expr Target.title_column title))
              |> command)
          in
          Cte.with_result (Postgresql.Cte.command command) ~f:(fun () ->
            Query.select_one (Expr.constant Db_type.int64 1L)))
      in
      match Compiler.compile ~dialect:Dialect.postgresql query with
      | Ok compiled ->
        String.is_substring (Compiled_query.sql compiled) ~substring:"USING \"c0\" AS t1"
      | Error _ -> false
    ;;

    let%test "a data-modifying CTE can feed MERGE at statement level" =
      let inserted =
        Postgresql.Cte.returning
          ~table:Source.table
          ~columns:Source.projection
          Insert.(
            into Source.table
            |> set Source.id_column 1L
            |> set Source.title_column "imported"
            |> returning Source.projection)
      in
      let command =
        Cte.with_command inserted ~f:(fun source ->
          Merge.(
            into Target.table
            |> using_cte source ~f:(fun target source merge ->
              merge
              |> on (Target.id target =. Source.id source)
              |> when_matched_do_nothing)
            |> command))
      in
      let rendered = sql command in
      String.is_prefix rendered ~prefix:"WITH"
      && String.is_substring rendered ~substring:"INSERT INTO"
      && String.is_substring rendered ~substring:"MERGE INTO"
    ;;

    let%test "MERGE command is valid as a top-level data-modifying CTE" =
      let definition = Postgresql.Cte.command Merge.(merge () |> command) in
      let query =
        Cte.with_result definition ~f:(fun () ->
          Query.select_one (Expr.constant Db_type.int64 1L))
      in
      match Compiler.compile ~dialect:Dialect.postgresql query with
      | Ok compiled ->
        String.is_substring (Compiled_query.sql compiled) ~substring:"MERGE INTO"
      | Error _ -> false
    ;;

    let%test "MERGE RETURNING supplies rows to a top-level CTE" =
      let definition =
        Postgresql.Cte.returning
          ~table:Target.table
          ~columns:Target.projection
          Merge.(merge () |> returning (fun target _ -> Target.projection target))
      in
      let query =
        Cte.with_result definition ~f:(fun target ->
          Query.(from_cte target |> select Target.projection))
      in
      match Compiler.compile ~dialect:Dialect.postgresql query with
      | Ok compiled ->
        String.is_substring (Compiled_query.sql compiled) ~substring:"RETURNING"
      | Error _ -> false
    ;;

    let%test "CTE handles cannot escape their definition scope" =
      let escaped = ref None in
      ignore
        (Cte.with_command selected ~f:(fun source ->
           escaped := Some source;
           Merge.(merge () |> command)));
      let command =
        Merge.(
          into Target.table
          |> using_cte (Option.value_exn !escaped) ~f:(fun _ _ merge ->
            merge |> on Condition.true_ |> when_matched_do_nothing)
          |> command)
      in
      match compile command with
      | Error (Compile_error.Unknown_cte _) -> true
      | Ok _ | Error _ -> false
    ;;

    module Number = struct
      type row

      let table : row Table.t = Table.v_exn "numbers"
      let value_column = Column.v_exn table "value" Db_type.int64
      let value row = Expr.column row value_column
      let projection row = Projection.expr (value row)
      let relation query = Derived_table.create ~table ~columns:projection query

      let recursive =
        Cte.recursive
          ~union:`Union_all
          ~anchor:(relation (Query.select_one (Expr.constant Db_type.int64 1L)))
          ~step:(fun numbers ->
            relation
              Query.(
                from_cte numbers
                |> where (fun number -> value number <$ 3L)
                |> select (fun number ->
                  let open Expr.Int64.Infix in
                  Projection.expr (value number +. Expr.constant Db_type.int64 1L))))
      ;;
    end

    let%test "WITH RECURSIVE directly on MERGE is rejected" =
      let command =
        Cte.with_command Number.recursive ~f:(fun numbers ->
          Merge.(
            into Target.table
            |> using_cte numbers ~f:(fun target source merge ->
              merge
              |> on (Target.id target =. Number.value source)
              |> when_matched_do_nothing)
            |> command))
      in
      match compile command |> Result.map_error ~f:Compile_error.to_string with
      | Error message ->
        String.equal
          message
          "invalid MERGE: WITH RECURSIVE is not supported directly by MERGE"
      | Ok _ -> false
    ;;

    let%test "independent recursive SELECT is allowed inside USING" =
      let recursive_query =
        Cte.with_result Number.recursive ~f:(fun numbers ->
          Query.(from_cte numbers |> select Number.projection))
      in
      let relation = Number.relation recursive_query in
      let command =
        Merge.(
          into Target.table
          |> using_derived relation ~f:(fun target source merge ->
            merge
            |> on (Target.id target =. Number.value source)
            |> when_matched_do_nothing)
          |> command)
      in
      String.is_substring (sql command) ~substring:"WITH RECURSIVE"
    ;;

    let%test "a top-level MERGE may contain a side-effect-only CTE" =
      let modified =
        Postgresql.Cte.command
          Update.(
            table Source.table |> set Source.title_column "updated" |> all_rows |> command)
      in
      let command =
        Cte.with_command modified ~f:(fun () -> Merge.(merge () |> command))
      in
      Result.is_ok (compile command)
    ;;

    let%test "nested data-modifying CTE is rejected inside USING" =
      let modified =
        Postgresql.Cte.command
          Update.(
            table Source.table |> set Source.title_column "updated" |> all_rows |> command)
      in
      let query =
        Cte.with_result modified ~f:(fun () ->
          Query.(from Source.table |> select Source.projection))
      in
      let relation =
        Derived_table.create ~table:Source.table ~columns:Source.projection query
      in
      let command =
        Merge.(
          into Target.table
          |> using_derived relation ~f:(fun _ _ merge ->
            merge |> on Condition.true_ |> when_matched_do_nothing)
          |> command)
      in
      match compile command |> Result.map_error ~f:Compile_error.to_string with
      | Error message ->
        String.equal
          message
          "data-modifying CTE must be attached to the top-level statement"
      | Ok _ -> false
    ;;

    let%test "RETURNING scalar subqueries see the MERGE statement CTEs" =
      let query =
        Cte.with_result selected ~f:(fun selected ->
          let count =
            Query.(from_cte selected |> select_scalar (fun _ -> Expr.count_all))
          in
          Merge.(
            merge ()
            |> returning (fun _ _ -> Projection.expr (Expr.scalar_subquery count))))
      in
      Result.is_ok (Compiler.compile ~dialect:Dialect.postgresql query)
    ;;
  end)
;;

let%test_module "MERGE statement parameters" =
  (module struct
    type input =
      { source_id : int64
      ; cutoff : int64
      ; condition : string
      ; replacement : string
      }

    let statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let%map.Statement.Parameters replacement =
          params.expr Db_type.text ~name:"replacement" ~get:(fun input ->
            input.replacement)
        and condition =
          params.expr Db_type.text ~name:"condition" ~get:(fun input -> input.condition)
        and cutoff =
          params.expr Db_type.int64 ~name:"cutoff" ~get:(fun input -> input.cutoff)
        and source_id =
          params.expr Db_type.int64 ~name:"source_id" ~get:(fun input -> input.source_id)
        in
        let relation =
          Derived_table.create
            ~table:Source.table
            ~columns:Source.projection
            Query.(
              from Source.table
              |> where (fun source -> Source.id source =. source_id)
              |> select Source.projection)
        in
        params.command
          Merge.(
            into Target.table
            |> using_derived relation ~f:(fun target source merge ->
              merge
              |> on
                   (Target.id target =. Source.id source &&. (Source.id source >=. cutoff))
              |> when_matched_update
                   ~condition:(Source.title source <>. condition)
                   Assignments.(empty |> set_expr Target.title_column replacement)
              |> when_not_matched_insert
                   Assignments.(empty |> set_expr Target.title_column replacement))
            |> command))
    ;;

    let input =
      { source_id = 11L; cutoff = 3L; condition = "ignored"; replacement = "updated" }
    ;;

    let%expect_test "static slots bind in SQL order and repeated slots are reused" =
      let _, inspection = Statement.inspect_exn ~dialect:Postgresql ~input statement in
      print_s (Sexp.List (List.map inspection.parameters ~f:Statement.sexp_of_parameter));
      [%expect
        {|
        (((position 1) (placeholder $1) (name (source_id)) (db_type int64)
          (dialect_type (bigint)) (value ((Encoded 11))))
         ((position 2) (placeholder $2) (name (cutoff)) (db_type int64)
          (dialect_type (bigint)) (value ((Encoded 3))))
         ((position 3) (placeholder $3) (name (condition)) (db_type text)
          (dialect_type (text)) (value ((Encoded ignored))))
         ((position 4) (placeholder $4) (name (replacement)) (db_type text)
          (dialect_type (text)) (value ((Encoded updated)))))
        |}]
    ;;

    let%test "static MERGE accepts omitted input for SQL and inspection metadata" =
      let rendered, inspection = Statement.inspect_exn ~dialect:Postgresql statement in
      String.equal rendered (Statement.sql_exn ~dialect:Postgresql ~input statement)
      && List.for_all inspection.parameters ~f:(fun parameter ->
        Option.is_none parameter.value)
      &&
      match inspection.output, inspection.tree with
      | Statement.Command_output, Statement.Leaf { kind = `Command; mode = `Static } ->
        true
      | _ -> false
    ;;

    let%test "runtime values preserve static MERGE SQL" =
      String.equal
        (Statement.sql_exn ~dialect:Postgresql ~input statement)
        (Statement.sql_exn
           ~dialect:Postgresql
           ~input:
             { source_id = 99L; cutoff = 42L; condition = "other"; replacement = "new" }
           statement)
    ;;

    let dynamic =
      Statement.Dynamic.command ~dialect:Dialect.postgresql (fun delete ->
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun target source merge ->
            let merge = merge |> on (Target.id target =. Source.id source) in
            if delete then
              merge |> when_matched_delete
            else
              merge
              |> when_matched_update
                   Assignments.(empty |> set Target.title_column "updated"))
          |> command))
    ;;

    let%test "dynamic MERGE inspects only the selected shape" =
      let delete_sql, inspection =
        Statement.inspect_exn ~dialect:Postgresql ~input:true dynamic
      in
      let update_sql = Statement.sql_exn ~dialect:Postgresql ~input:false dynamic in
      String.is_substring delete_sql ~substring:"DELETE"
      && String.is_substring update_sql ~substring:"UPDATE SET"
      && List.is_empty inspection.parameters
      &&
      match inspection.tree with
      | Statement.Leaf { kind = `Command; mode = `Dynamic } -> true
      | _ -> false
    ;;

    let%test "dynamic MERGE inspection needs its runtime input" =
      match Statement.inspect ~dialect:Postgresql dynamic with
      | Error (Statement.Statement_error Statement.Dynamic_input_required) -> true
      | Ok _ | Error _ -> false
    ;;
  end)
;;

let%test_module "MERGE SQL structure properties" =
  (module struct
    let with_values id title =
      Merge.(
        into Target.table
        |> using Source.table ~f:(fun target source merge ->
          merge
          |> on (Target.id target =. Source.id source)
          |> when_matched_update Assignments.(empty |> set Target.title_column title)
          |> when_not_matched_insert Assignments.(empty |> set Target.id_column id))
        |> command)
    ;;

    let%test_unit "bind values and recreated source identities preserve SQL" =
      QCheck.Test.make
        ~count:100
        QCheck.(pair nat_small string)
        (fun (id, title) ->
           String.equal
             (sql (with_values (Int64.of_int id) title))
             (sql (with_values 1L "baseline")))
      |> QCheck.Test.check_exn ~rand:(Stdlib.Random.State.make [| 40; 50 |])
    ;;

    let%test "changing branch order changes the SQL structure" =
      let command first_delete =
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun _ source merge ->
            let merge = merge |> on Condition.true_ in
            let delete merge =
              when_matched_delete ~condition:(Source.id source <$ 0L) merge
            in
            let update merge =
              when_matched_update
                ~condition:(Source.id source >$ 0L)
                Assignments.(empty |> set Target.title_column "updated")
                merge
            in
            if first_delete then
              merge |> delete |> update
            else
              merge |> update |> delete)
          |> command)
      in
      not (String.equal (sql (command true)) (sql (command false)))
    ;;

    let%test "changing a branch predicate changes the SQL structure" =
      let command equal =
        Merge.(
          into Target.table
          |> using Source.table ~f:(fun _ source merge ->
            let condition =
              if equal then
                Source.id source =$ 1L
              else
                Source.id source >$ 1L
            in
            merge |> on Condition.true_ |> when_matched_do_nothing ~condition)
          |> command)
      in
      not (String.equal (sql (command true)) (sql (command false)))
    ;;

    let%test_unit "adding a branch does not mutate an existing builder" =
      let original = merge () in
      let before = Merge.(original |> command) |> sql in
      let changed =
        Merge.(original |> when_matched_delete ~condition:Condition.false_ |> command)
      in
      ignore (compile changed);
      assert (String.equal before (Merge.(original |> command) |> sql))
    ;;
  end)
;;

let%expect_test "empty MERGE diagnostic has a stable structured representation" =
  print_s (Compile_error.sexp_of_t Compile_error.Empty_merge_branches);
  [%expect {| Empty_merge_branches |}]
;;

let%expect_test "empty MERGE assignments diagnostic preserves branch and action" =
  print_s
    (Compile_error.sexp_of_t
       (Compile_error.Empty_merge_assignments { branch = 2; action = `Insert }));
  [%expect {| (Empty_merge_assignments (branch 2) (action Insert)) |}]
;;

let%expect_test "unreachable MERGE diagnostic preserves branch and match kind" =
  print_s
    (Compile_error.sexp_of_t
       (Compile_error.Unreachable_merge_branch { branch = 3; kind = `Not_matched }));
  [%expect {| (Unreachable_merge_branch (branch 3) (kind Not_matched)) |}]
;;

let%expect_test "invalid MERGE diagnostic preserves its reason" =
  print_s (Compile_error.sexp_of_t (Compile_error.Invalid_merge "invalid source"));
  [%expect {| (Invalid_merge "invalid source") |}]
;;

let%expect_test "modifying CTE placement has a stable structured diagnostic" =
  print_s (Compile_error.sexp_of_t Compile_error.Invalid_cte_placement);
  [%expect {| Invalid_cte_placement |}]
;;
