open! Base
open Typed_sql
open Statement_compile
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "validation_items"
  let id = Column.v_exn table "id" Db_type.int64
  let other = Column.v_exn table "other" Db_type.int64
  let text = Column.v_exn table "text" Db_type.text
end

let aggregate_error clause = function
  | Error (Compile_error.Aggregate_not_allowed actual) -> String.equal clause actual
  | _ -> false
;;

let%test_module "DML aggregate scope" =
  (module struct
    let count () =
      Query.(from Item.table |> select_scalar (fun _ -> Expr.count_all))
      |> Expr.scalar_subquery
      |> Expr.coalesce ~default:(Expr.constant Db_type.int64 0L)
    ;;

    let%test "UPDATE SET rejects COUNT" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> set Assignment.[ expr Item.id Expr.count_all ]
          |> all_rows
          |> command)
      |> aggregate_error "UPDATE SET"
    ;;

    let%test "UPDATE SET accepts a local aggregate subquery" =
      Compiler.compile_command
        ~dialect:Dialect.portable
        Update.(
          table Item.table
          |> set Assignment.[ expr Item.id (count ()) ]
          |> all_rows
          |> command)
      |> Result.is_ok
    ;;

    let%test "UPDATE WHERE rejects COUNT" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> set Assignment.[ value Item.id 1L ]
          |> where (fun _ -> Expr.count_all >$ 0L)
          |> command)
      |> aggregate_error "UPDATE WHERE"
    ;;

    let%test "UPDATE WHERE accepts a local aggregate subquery" =
      Compiler.compile_command
        ~dialect:Dialect.portable
        Update.(
          table Item.table
          |> set Assignment.[ value Item.id 1L ]
          |> where (fun _ -> count () >$ 0L)
          |> command)
      |> Result.is_ok
    ;;

    let%test "DELETE WHERE rejects COUNT" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Delete.(from Item.table |> where (fun _ -> Expr.count_all >$ 0L) |> command)
      |> aggregate_error "DELETE WHERE"
    ;;

    let%test "DELETE WHERE accepts a local aggregate subquery" =
      Compiler.compile_command
        ~dialect:Dialect.portable
        Delete.(from Item.table |> where (fun _ -> count () >$ 0L) |> command)
      |> Result.is_ok
    ;;

    let%test "INSERT RETURNING rejects COUNT" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Insert.(
          into Item.table
          |> values Assignment.[ value Item.id 1L ]
          |> returning (fun _ -> Projection.expr Expr.count_all))
      |> aggregate_error "INSERT RETURNING"
    ;;

    let%test "INSERT RETURNING accepts a local aggregate subquery" =
      Compiler.compile
        ~dialect:Dialect.portable
        Insert.(
          into Item.table
          |> values Assignment.[ value Item.id 1L ]
          |> returning (fun _ -> Projection.expr (count ())))
      |> Result.is_ok
    ;;

    let%test "UPDATE RETURNING rejects COUNT" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> set Assignment.[ value Item.id 1L ]
          |> all_rows
          |> returning (fun _ -> Projection.expr Expr.count_all))
      |> aggregate_error "UPDATE RETURNING"
    ;;

    let%test "UPDATE RETURNING accepts a local aggregate subquery" =
      Compiler.compile
        ~dialect:Dialect.portable
        Update.(
          table Item.table
          |> set Assignment.[ value Item.id 1L ]
          |> all_rows
          |> returning (fun _ -> Projection.expr (count ())))
      |> Result.is_ok
    ;;

    let%test "DELETE RETURNING rejects COUNT" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Delete.(
          from Item.table
          |> all_rows
          |> returning (fun _ -> Projection.expr Expr.count_all))
      |> aggregate_error "DELETE RETURNING"
    ;;

    let%test "DELETE RETURNING accepts a local aggregate subquery" =
      Compiler.compile
        ~dialect:Dialect.portable
        Delete.(
          from Item.table |> all_rows |> returning (fun _ -> Projection.expr (count ())))
      |> Result.is_ok
    ;;

    let outer_count parent =
      Query.(
        from Item.table
        |> limit_one
        |> select_scalar (fun _ -> Expr.count (Expr.column parent Item.id)))
      |> Expr.scalar_subquery
      |> Expr.coalesce ~default:(Expr.constant Db_type.int64 0L)
    ;;

    let%test "UPDATE SET rejects an aggregate owned by the outer DML scope" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> with_target ~f:(fun parent update ->
            set Assignment.[ expr Item.id (outer_count parent) ] update)
          |> all_rows
          |> command)
      |> aggregate_error "UPDATE SET"
    ;;

    let%test "DELETE WHERE rejects an aggregate owned by the outer DML scope" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Delete.(
          from Item.table |> where (fun parent -> outer_count parent >$ 0L) |> command)
      |> aggregate_error "DELETE WHERE"
    ;;

    let%test "UPDATE RETURNING rejects an outer aggregate in a subquery" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> set Assignment.[ value Item.id 1L ]
          |> all_rows
          |> returning (fun parent -> Projection.expr (outer_count parent)))
      |> aggregate_error "UPDATE RETURNING"
    ;;
  end)
;;

let%test_module "aggregate clause ownership" =
  (module struct
    let local_count () =
      Expr.coalesce
        (Expr.scalar_subquery
           Query.(from Item.table |> select_scalar (fun _ -> Expr.count_all)))
        ~default:(Expr.constant Db_type.int64 0L)
    ;;

    let outer_count row =
      Expr.coalesce
        (Expr.scalar_subquery
           Query.(
             from Item.table
             |> limit_one
             |> select_scalar (fun _ -> Expr.count (Expr.column row Item.id))))
        ~default:(Expr.constant Db_type.int64 0L)
    ;;

    let%test "SELECT WHERE rejects a subquery aggregate owned by SELECT" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> where (fun row -> outer_count row >$ 0L)
          |> select (fun row -> Projection.expr (Expr.column row Item.id)))
      |> aggregate_error "WHERE"
    ;;

    let%test "SELECT WHERE permits a local subquery aggregate" =
      Compiler.compile
        ~dialect:Dialect.portable
        Query.(
          from Item.table
          |> where (fun _ -> local_count () >$ 0L)
          |> select (fun row -> Projection.expr (Expr.column row Item.id)))
      |> Result.is_ok
    ;;

    let%test "JOIN ON rejects a subquery aggregate owned by SELECT" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> inner_join Item.table ~on:(fun row _ -> outer_count row >$ 0L)
          |> select (fun (row, _) -> Projection.expr (Expr.column row Item.id)))
      |> aggregate_error "JOIN ON"
    ;;

    let%test "JOIN ON permits a local subquery aggregate" =
      Compiler.compile
        ~dialect:Dialect.portable
        Query.(
          from Item.table
          |> inner_join Item.table ~on:(fun _ _ -> local_count () >$ 0L)
          |> select (fun (row, _) -> Projection.expr (Expr.column row Item.id)))
      |> Result.is_ok
    ;;

    let%test "GROUP BY rejects a subquery aggregate owned by SELECT" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> group_by outer_count
          |> select (fun _ -> Projection.expr Expr.count_all))
      |> aggregate_error "GROUP BY"
    ;;

    let%test "GROUP BY permits a local subquery aggregate" =
      Compiler.compile
        ~dialect:Dialect.portable
        Query.(
          from Item.table
          |> group_by (fun _ -> local_count ())
          |> select (fun _ -> Projection.expr Expr.count_all))
      |> Result.is_ok
    ;;

    let%test "inner WHERE does not claim an aggregate owned by its outer SELECT" =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> select (fun row ->
            Projection.expr
              (Expr.scalar_subquery
                 Query.(
                   from Item.table
                   |> where (fun _ -> outer_count row >$ 0L)
                   |> limit_one
                   |> select_scalar (fun _ -> Expr.constant Db_type.int64 1L)))))
      |> Result.is_ok
    ;;

    let upsert f =
      Insert.(
        into Item.table
        |> values Assignment.[ value Item.id 1L ]
        |> on_conflict (Conflict_target.column Item.id)
        |> do_update f
        |> command)
    ;;

    let%test "conflict SET rejects a subquery aggregate owned by the existing row" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        (upsert (fun ~existing ~excluded:_ ->
           Insert.Conflict_update.(
             empty |> set Assignment.[ expr Item.id (outer_count existing) ])))
      |> aggregate_error "ON CONFLICT DO UPDATE SET"
    ;;

    let%test "conflict SET rejects a subquery aggregate owned by the excluded row" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        (upsert (fun ~existing:_ ~excluded ->
           Insert.Conflict_update.(
             empty |> set Assignment.[ expr Item.id (outer_count excluded) ])))
      |> aggregate_error "ON CONFLICT DO UPDATE SET"
    ;;

    let%test "conflict SET permits a local subquery aggregate" =
      Compiler.compile_command
        ~dialect:Dialect.portable
        (upsert (fun ~existing:_ ~excluded:_ ->
           Insert.Conflict_update.(
             empty |> set Assignment.[ expr Item.id (local_count ()) ])))
      |> Result.is_ok
    ;;

    let%test "conflict WHERE rejects a subquery aggregate owned by the existing row" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        (upsert (fun ~existing ~excluded:_ ->
           Insert.Conflict_update.(
             empty
             |> set Assignment.[ value Item.id 2L ]
             |> where (outer_count existing >$ 0L))))
      |> aggregate_error "ON CONFLICT DO UPDATE WHERE"
    ;;

    let%test "conflict WHERE rejects a subquery aggregate owned by the excluded row" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        (upsert (fun ~existing:_ ~excluded ->
           Insert.Conflict_update.(
             empty
             |> set Assignment.[ value Item.id 2L ]
             |> where (outer_count excluded >$ 0L))))
      |> aggregate_error "ON CONFLICT DO UPDATE WHERE"
    ;;

    let%test "conflict WHERE permits a local subquery aggregate" =
      Compiler.compile_command
        ~dialect:Dialect.portable
        (upsert (fun ~existing:_ ~excluded:_ ->
           Insert.Conflict_update.(
             empty |> set Assignment.[ value Item.id 2L ] |> where (local_count () >$ 0L))))
      |> Result.is_ok
    ;;

    let%test "INSERT VALUES rejects a direct aggregate" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Insert.(
          into Item.table |> values Assignment.[ expr Item.id Expr.count_all ] |> command)
      |> aggregate_error "INSERT VALUES"
    ;;

    let%test "INSERT VALUES checks later rows for direct aggregates" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Insert.(
          rows
            Item.table
            [ Assignment.[ value Item.id 1L ]
            ; Assignment.[ expr Item.id Expr.count_all ]
            ]
          |> command)
      |> aggregate_error "INSERT VALUES"
    ;;

    let%test "INSERT VALUES permits a local subquery aggregate" =
      Compiler.compile_command
        ~dialect:Dialect.portable
        Insert.(
          into Item.table
          |> values Assignment.[ expr Item.id (local_count ()) ]
          |> command)
      |> Result.is_ok
    ;;
  end)
;;

let%test_module "SQL identity" =
  (module struct
    let named name =
      Db_type.Postgresql.named
        ~schema:(Identifier.of_string_exn "public")
        ~name:(Identifier.of_string_exn name)
        Db_type.text
    ;;

    let left_type = named "left_status"
    let right_type = named "right_status"
    let left = Expr.constant left_type "ready"
    let right = Expr.constant right_type "ready"
    let left_column = Column.v_exn Item.table "left_status" left_type
    let right_column = Column.v_exn Item.table "right_status" right_type

    let mismatch = function
      | Error (Compile_error.Mismatched_sql_type _) -> true
      | _ -> false
    ;;

    let query condition =
      Query.(
        from Item.table
        |> where (fun _ -> condition)
        |> select (fun row -> Projection.expr (Expr.column row Item.id)))
    ;;

    let compile query = Compiler.compile ~dialect:Dialect.postgresql query

    let%expect_test "different enums report SQL types, not just their OCaml type" =
      (match compile (query (left =. right)) with
       | Error error -> Stdlib.print_endline (Compile_error.to_string error)
       | Ok _ -> failwith "different enums compared successfully");
      [%expect
        {| comparison: expected SQL type "public"."left_status", got "public"."right_status" |}]
    ;;

    let%test "same enum accepts distinct descriptors" =
      compile (query (left =. Expr.constant (named "left_status") "ready"))
      |> Result.is_ok
    ;;

    let%test "CASE rejects different enums" =
      compile (Query.select_one (Expr.case [ Condition.true_, left ] ~else_:right))
      |> mismatch
    ;;

    let%test "COALESCE rejects different enums" =
      compile (Query.select_one (Expr.coalesce (Expr.to_nullable left) ~default:right))
      |> mismatch
    ;;

    let%test "IN rejects different enums" =
      compile (query (Expr.in_exprs left [ right ])) |> mismatch
    ;;

    let%test "NOT IN rejects different enums" =
      compile (query (Expr.not_in_exprs left [ right ])) |> mismatch
    ;;

    let%test "BETWEEN checks its lower bound" =
      compile (query (Expr.between_exprs left ~lower:right ~upper:left)) |> mismatch
    ;;

    let%test "BETWEEN checks its upper bound" =
      compile (query (Expr.between_exprs left ~lower:left ~upper:right)) |> mismatch
    ;;

    let%test "UPDATE assignment checks the target descriptor" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> set Assignment.[ expr left_column right ]
          |> all_rows
          |> command)
      |> mismatch
    ;;

    let%test "INSERT assignment checks the target descriptor" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Insert.(
          into Item.table |> values Assignment.[ expr left_column right ] |> command)
      |> mismatch
    ;;

    let%test "conflict update checks the target descriptor" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Insert.(
          into Item.table
          |> values Assignment.[ value left_column "ready" ]
          |> on_conflict (Conflict_target.column left_column)
          |> do_update (fun ~existing:_ ~excluded ->
            Conflict_update.(
              empty
              |> set Assignment.[ expr left_column (Expr.column excluded right_column) ]))
          |> command)
      |> mismatch
    ;;

    let%test "explicit nullable assignment still checks the base SQL type" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> set_nullable_expr left_column (Expr.to_nullable right)
          |> all_rows
          |> command)
      |> mismatch
    ;;

    let%test "nullable assignment with the same enum is allowed" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Update.(
          table Item.table
          |> set_nullable_expr left_column (Expr.to_nullable left)
          |> all_rows
          |> command)
      |> Result.is_ok
    ;;

    let%test "mapped codecs retain their underlying SQL identity" =
      let mapped =
        Db_type.map
          ~name:"trimmed"
          ~encode:Result.return
          ~decode:(fun value -> Ok (String.strip value))
          Db_type.text
      in
      compile (query (Expr.constant mapped "ready" =. Expr.constant Db_type.text "ready"))
      |> Result.is_ok
    ;;

    let%test "pg_catalog aliases retain builtin SQL identity" =
      let text =
        Db_type.Postgresql.named
          ~schema:(Identifier.of_string_exn "pg_catalog")
          ~name:(Identifier.of_string_exn "text")
          Db_type.text
      in
      compile (query (Expr.constant text "ready" =. Expr.constant Db_type.text "ready"))
      |> Result.is_ok
    ;;
  end)
;;

let%test_module "GROUP BY CASE" =
  (module struct
    let threshold = Expr.constant Db_type.int64 0L
    let yes = Expr.constant Db_type.text "positive"
    let no = Expr.constant Db_type.text "other"
    let bucket row = Expr.case [ Expr.column row Item.id >. threshold, yes ] ~else_:no

    let query =
      Query.(
        from Item.table
        |> group_by bucket
        |> select (fun row ->
          Projection.both (Projection.expr (bucket row)) (Projection.expr Expr.count_all)))
    ;;

    let print dialect =
      Compiler.compile ~dialect query
      |> Result.map_error ~f:Compile_error.to_string
      |> Result.ok_or_failwith
      |> Compiled_query.sql
      |> Stdlib.print_endline
    ;;

    let%expect_test "PostgreSQL reuses CASE bind parameters" =
      print Dialect.postgresql;
      [%expect
        {|
        SELECT
          (CASE
            WHEN (t0."id" > $1) THEN $2
            ELSE $3
          END),
          COUNT(*)
        FROM "validation_items" AS t0
        GROUP BY
          (CASE
            WHEN (t0."id" > $1) THEN $2
            ELSE $3
          END)
      |}]
    ;;

    let%expect_test "SQLite reuses CASE bind parameters" =
      print Dialect.sqlite;
      [%expect
        {|
        SELECT
          (CASE
            WHEN (t0."id" > ?1) THEN ?2
            ELSE ?3
          END),
          COUNT(*)
        FROM "validation_items" AS t0
        GROUP BY
          (CASE
            WHEN (t0."id" > ?1) THEN ?2
            ELSE ?3
          END)
      |}]
    ;;

    let%test "recreated constants do not identify CASE groups" =
      let fresh_bucket row =
        Expr.case
          [ Expr.column row Item.id >$ 0L, Expr.constant Db_type.text "positive" ]
          ~else_:(Expr.constant Db_type.text "other")
      in
      match
        Compiler.compile
          ~dialect:Dialect.portable
          Query.(
            from Item.table
            |> group_by fresh_bucket
            |> select (fun row -> Projection.expr (fresh_bucket row)))
      with
      | Error Compile_error.Ungrouped_expression -> true
      | _ -> false
    ;;

    let%test "different CASE conditions remain ungrouped" =
      let other row =
        Expr.case [ Expr.column row Item.other >. threshold, yes ] ~else_:no
      in
      match
        Compiler.compile
          ~dialect:Dialect.postgresql
          Query.(
            from Item.table
            |> group_by bucket
            |> select (fun row -> Projection.expr (other row)))
      with
      | Error Compile_error.Ungrouped_expression -> true
      | _ -> false
    ;;
  end)
;;

let%test "identifier accepts exactly 63 bytes" =
  Result.is_ok (Identifier.of_string (String.make 63 'x'))
;;

let%test "identifier rejects 64 bytes" =
  match Identifier.of_string (String.make 64 'x') with
  | Error (`Too_long 64) -> true
  | _ -> false
;;

let%test "identifier counts UTF-8 bytes" =
  match Identifier.of_string (String.concat (List.init 32 ~f:(fun _ -> "я"))) with
  | Error (`Too_long 64) -> true
  | _ -> false
;;

let%test "identifier accepts a UTF-8 name within the byte limit" =
  Result.is_ok
    (Identifier.of_string (String.concat (List.init 31 ~f:(fun _ -> "я")) ^ "x"))
;;

let%test "identifier throwing variant reports excessive length" =
  match Identifier.of_string_exn (String.make 64 'x') with
  | exception Stdlib.Invalid_argument message ->
    String.equal message "SQL identifier must be at most 63 bytes, got 64"
  | _ -> false
;;

let%expect_test "identifier length error is structural and formatted" =
  let error = `Too_long 64 in
  Stdlib.print_endline (Identifier.error_to_string error);
  [%expect {| SQL identifier must be at most 63 bytes, got 64 |}];
  Identifier.sexp_of_error error |> Sexp.to_string_hum |> Stdlib.print_endline;
  [%expect {| (Too_long 64) |}]
;;

let%test "Date roundtrips the lower Ptime bound" =
  match Date.of_string "0000-01-01" with
  | Some date -> String.equal (Date.to_string date) "0000-01-01"
  | None -> false
;;

let%test "Date roundtrips the upper Ptime bound" =
  match Date.of_string "9999-12-31" with
  | Some date -> String.equal (Date.to_string date) "9999-12-31"
  | None -> false
;;

let%test "Date rejects BC text" = Option.is_none (Date.of_string "0001-01-01 BC")
let%test "Date rejects a five-digit year" = Option.is_none (Date.of_string "10000-01-01")
let%test "Date rejects positive infinity" = Option.is_none (Date.of_string "infinity")
let%test "Date rejects negative infinity" = Option.is_none (Date.of_string "-infinity")

let%test_module "grouped CASE conditions" =
  (module struct
    let bound = Expr.constant Db_type.int64 0L
    let upper = Expr.constant Db_type.int64 9L
    let yes = Expr.constant Db_type.text "yes"
    let no = Expr.constant Db_type.text "no"
    let pattern = Expr.constant Db_type.text "y%"
    let array = Expr.constant (Db_type.Postgresql.array_list Db_type.int64) [ 0L; 9L ]
    let id row = Expr.column row Item.id
    let text row = Expr.column row Item.text

    let grouped condition =
      let bucket row = Expr.case [ condition row, yes ] ~else_:no in
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> group_by bucket
          |> select (fun row -> Projection.expr (bucket row)))
      |> Result.is_ok
    ;;

    let%test "equality condition" = grouped (fun row -> id row =. bound)
    let%test "inequality condition" = grouped (fun row -> id row <>. bound)
    let%test "less-than condition" = grouped (fun row -> id row <. bound)
    let%test "less-or-equal condition" = grouped (fun row -> id row <=. bound)
    let%test "greater-or-equal condition" = grouped (fun row -> id row >=. bound)
    let%test "LIKE condition" = grouped (fun row -> text row =~. pattern)

    let%test "null-safe comparison condition" =
      grouped (fun row -> Expr.is_distinct_from (id row) bound)
    ;;

    let%test "constant true condition" = grouped (fun _ -> Condition.true_)
    let%test "constant false condition" = grouped (fun _ -> Condition.false_)

    let%test "IS NULL condition" =
      grouped (fun row -> Expr.is_null (Expr.to_nullable (id row)))
    ;;

    let%test "IS NOT NULL condition" =
      grouped (fun row -> Expr.is_not_null (Expr.to_nullable (id row)))
    ;;

    let%test "IN condition" = grouped (fun row -> Expr.in_exprs (id row) [ bound; upper ])

    let%test "NOT IN condition" =
      grouped (fun row -> Expr.not_in_exprs (id row) [ bound; upper ])
    ;;

    let%test "BETWEEN condition" =
      grouped (fun row -> Expr.between_exprs (id row) ~lower:bound ~upper)
    ;;

    let%test "AND condition" = grouped (fun row -> id row >. bound &&. (id row <. upper))
    let%test "OR condition" = grouped (fun row -> id row <. bound ||. (id row >. upper))
    let%test "NOT condition" = grouped (fun row -> Condition.not_ (id row =. bound))

    let%test "ANY condition" =
      grouped (fun row -> Postgresql.Expr.equals_any_list (id row) array)
    ;;

    let%test "different comparison operators do not identify groups" =
      let bucket comparison row =
        Expr.case [ comparison (id row) bound, yes ] ~else_:no
      in
      match
        Compiler.compile
          ~dialect:Dialect.postgresql
          Query.(
            from Item.table
            |> group_by (bucket ( =. ))
            |> select (fun row -> Projection.expr (bucket ( <>. ) row)))
      with
      | Error Compile_error.Ungrouped_expression -> true
      | _ -> false
    ;;

    let%test "different condition kinds do not identify groups" =
      let bucket condition row = Expr.case [ condition row, yes ] ~else_:no in
      match
        Compiler.compile
          ~dialect:Dialect.postgresql
          Query.(
            from Item.table
            |> group_by (bucket (fun row -> Expr.is_null (Expr.to_nullable (id row))))
            |> select (fun row ->
              Projection.expr
                (bucket (fun row -> Expr.is_not_null (Expr.to_nullable (id row))) row)))
      with
      | Error Compile_error.Ungrouped_expression -> true
      | _ -> false
    ;;

    let%test "runtime slot identity is retained inside CASE" =
      let statement =
        Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
          let%map.Parameters threshold = params.column Item.id ~get:Fn.id in
          let bucket row = Expr.case [ id row >. threshold, yes ] ~else_:no in
          params.query_many
            Query.(
              from Item.table
              |> group_by bucket
              |> select (fun row -> Projection.expr (bucket row))))
      in
      let sql = Statement.sql_exn ~dialect:Postgresql ~input:0L statement in
      String.is_substring sql ~substring:"GROUP BY"
      && Int.equal
           (List.length
              (snd (Statement.inspect_exn ~dialect:Postgresql ~input:0L statement))
                .parameters)
           3
    ;;

    let%test "different runtime slots do not identify CASE groups" =
      match
        Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
          let%map.Parameters a = params.column Item.id ~get:fst
          and b = params.column Item.id ~get:snd in
          let bucket threshold row = Expr.case [ id row >. threshold, yes ] ~else_:no in
          params.query_many
            Query.(
              from Item.table
              |> group_by (bucket a)
              |> select (fun row -> Projection.expr (bucket b row))))
      with
      | exception
          Statement.Definition_error { error = Compile_error.Ungrouped_expression; _ } ->
        true
      | _ -> false
    ;;

    let%test "CURRENT_TIMESTAMP is identified inside a grouping expression" =
      let now = Expr.current_timestamp in
      let bucket row = Expr.case [ id row >. bound, now ] ~else_:now in
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> group_by bucket
          |> select (fun row -> Projection.expr (bucket row)))
      |> Result.is_ok
    ;;
  end)
;;

let%test_module "SQL type derivation" =
  (module struct
    let check descriptor expression =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> group_by (fun row -> Expr.column row Item.id)
          |> select (fun row ->
            Projection.expr
              (Expr.case
                 [ Expr.column row Item.id >$ 0L, expression row ]
                 ~else_:(Expr.constant (Db_type.option descriptor) None))))
      |> Result.is_ok
    ;;

    let%test "COUNT DISTINCT yields bigint" =
      check Db_type.int64 (fun row ->
        Expr.to_nullable (Expr.count_distinct (Expr.column row Item.id)))
    ;;

    let%test "SUM int yields bigint" =
      check Db_type.int64 (fun _ -> Expr.sum_int (Expr.constant Db_type.int 1))
    ;;

    let%test "SUM float yields double precision" =
      check Db_type.float (fun _ -> Expr.sum_float (Expr.constant Db_type.float 1.))
    ;;

    let%test "AVG float yields double precision" =
      check Db_type.float (fun _ -> Expr.avg_float (Expr.constant Db_type.float 1.))
    ;;

    let%test "SUM bigint yields numeric" =
      check Db_type.numeric (fun row ->
        Postgresql.Numeric.sum_int64 (Expr.column row Item.id))
    ;;

    let%test "SUM numeric yields numeric" =
      check Db_type.numeric (fun _ ->
        Postgresql.Numeric.sum_numeric
          (Expr.constant Db_type.numeric (Decimal.of_string "1" |> Option.value_exn)))
    ;;

    let%test "AVG numeric yields numeric" =
      check Db_type.numeric (fun _ ->
        Postgresql.Numeric.avg_numeric
          (Expr.constant Db_type.numeric (Decimal.of_string "1" |> Option.value_exn)))
    ;;

    let%test "MIN preserves the named SQL type" =
      let typ =
        Db_type.Postgresql.named
          ~schema:(Identifier.of_string_exn "public")
          ~name:(Identifier.of_string_exn "status")
          Db_type.text
      in
      check typ (fun _ -> Expr.min Db_type.Orderable.text (Expr.constant typ "ready"))
    ;;

    let scalar descriptor expression =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> where (fun _ ->
            Expr.is_null
              (Expr.to_nullable
                 (Expr.coalesce (Expr.to_nullable expression) ~default:expression)))
          |> select (fun _ -> Projection.expr (Expr.constant descriptor 0)))
      |> Result.is_ok
    ;;

    let%test "LENGTH yields integer" =
      scalar Db_type.int (Expr.length (Expr.constant Db_type.text "hello"))
    ;;

    let%test "CAST to float yields double precision" =
      scalar Db_type.int (Expr.cast_int_to_float (Expr.constant Db_type.int 1))
    ;;

    let%test "CAST to numeric yields numeric" =
      scalar
        Db_type.int
        (Postgresql.Numeric.cast_int_to_numeric (Expr.constant Db_type.int 1))
    ;;

    let named_builtin descriptor name value =
      let typ =
        Db_type.Postgresql.named
          ~schema:(Identifier.of_string_exn "pg_catalog")
          ~name:(Identifier.of_string_exn name)
          descriptor
      in
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> where (fun _ -> Expr.constant typ value =. Expr.constant descriptor value)
          |> select (fun row -> Projection.expr (Expr.column row Item.id)))
      |> Result.is_ok
    ;;

    let%test "PostgreSQL bool has builtin identity" =
      named_builtin Db_type.bool "bool" true
    ;;

    let%test "PostgreSQL int4 has builtin identity" = named_builtin Db_type.int "int4" 1

    let%test "PostgreSQL int8 has builtin identity" =
      named_builtin Db_type.int64 "int8" 1L
    ;;

    let%test "PostgreSQL float8 has builtin identity" =
      named_builtin Db_type.float "float8" 1.
    ;;

    let%test "PostgreSQL timestamptz has builtin identity" =
      named_builtin
        Db_type.timestamp
        "timestamptz"
        (Date.of_string "2026-01-01" |> Option.value_exn |> Date.to_ptime)
    ;;

    let%test "PostgreSQL bytea has builtin identity" =
      named_builtin Db_type.bytes "bytea" (Bytes.of_string "x")
    ;;

    let%test "PostgreSQL date has builtin identity" =
      named_builtin Db_type.date "date" (Date.of_string "2026-01-01" |> Option.value_exn)
    ;;

    let%test "PostgreSQL numeric has builtin identity" =
      named_builtin Db_type.numeric "numeric" (Decimal.of_string "1" |> Option.value_exn)
    ;;

    let%test "PostgreSQL uuid has builtin identity" =
      named_builtin
        Db_type.uuid
        "uuid"
        (Uuid.of_string_exn "00000000-0000-0000-0000-000000000001")
    ;;
  end)
;;

let%test_module "named type boundaries" =
  (module struct
    let named name =
      Db_type.Postgresql.named
        ~schema:(Identifier.of_string_exn "public")
        ~name:(Identifier.of_string_exn name)
        Db_type.text
    ;;

    let left_type = named "left_status"
    let right_type = named "right_status"
    let target = Column.v_exn Item.table "left_status" left_type
    let source = Column.v_exn Item.table "right_status" right_type

    let mismatch = function
      | Error (Compile_error.Mismatched_sql_type _) -> true
      | _ -> false
    ;;

    let compare condition =
      Compiler.compile
        ~dialect:Dialect.postgresql
        Query.(
          from Item.table
          |> where (fun _ -> condition)
          |> select (fun row -> Projection.expr (Expr.column row Item.id)))
    ;;

    let%test "arrays retain their named element SQL type" =
      compare
        (Expr.constant (Db_type.Postgresql.array_list left_type) [ "ready" ]
         =. Expr.constant (Db_type.Postgresql.array_list right_type) [ "ready" ])
      |> mismatch
    ;;

    let%test "ANY checks a named array element type" =
      compare
        (Postgresql.Expr.equals_any_list
           (Expr.constant left_type "ready")
           (Expr.constant (Db_type.Postgresql.array_list right_type) [ "ready" ]))
      |> mismatch
    ;;

    let%test "scalar subquery retains its named result type" =
      let scalar =
        Query.(
          from Item.table
          |> limit_one
          |> select_scalar (fun row -> Expr.column row source))
      in
      compare
        (Expr.to_nullable (Expr.constant left_type "ready") =. Expr.scalar_subquery scalar)
      |> mismatch
    ;;

    let%test "IN subquery checks a named result type" =
      let scalar =
        Query.(from Item.table |> select_scalar (fun row -> Expr.column row source))
      in
      compare (Query.in_subquery (Expr.constant left_type "ready") scalar) |> mismatch
    ;;

    let%test "MERGE assignments retain the target descriptor" =
      Compiler.compile_command
        ~dialect:Dialect.postgresql
        Merge.(
          into Item.table
          |> using Item.table ~f:(fun existing incoming merge ->
            merge
            |> on (Expr.column existing Item.id =. Expr.column incoming Item.id)
            |> when_matched_update
                 Assignment.[ expr target (Expr.column incoming source) ])
          |> command)
      |> mismatch
    ;;

    let%test "dynamic statements return structured SQL type failures" =
      let statement =
        Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
          Query.(
            from Item.table
            |> where (fun row -> Expr.column row target =. Expr.column row source)
            |> select (fun row -> Projection.expr (Expr.column row Item.id))))
      in
      match Statement.sql ~dialect:Postgresql ~input:() statement with
      | Error
          (Statement.Compilation_error { error = Compile_error.Mismatched_sql_type _; _ })
        -> true
      | _ -> false
    ;;

    let%expect_test "SQL mismatch has a structured diagnostic" =
      let error =
        Compile_error.Mismatched_sql_type
          { context = "CASE"
          ; expected = "public.left_status"
          ; actual = "public.right_status"
          }
      in
      Compile_error.sexp_of_t error |> Sexp.to_string_hum |> Stdlib.print_endline;
      [%expect
        {|
        (Mismatched_sql_type (context CASE) (expected public.left_status)
         (actual public.right_status))
      |}]
    ;;

    let%test "jsonb mapping uses PostgreSQL SQL identity" =
      let typ =
        Db_type.Postgresql.named
          ~schema:(Identifier.of_string_exn "pg_catalog")
          ~name:(Identifier.of_string_exn "jsonb")
          Db_type.Postgresql.jsonb
      in
      compare
        (Expr.constant typ (`Assoc [])
         =. Expr.constant Db_type.Postgresql.jsonb (`Assoc []))
      |> Result.is_ok
    ;;
  end)
;;

let%test_module "operator SQL descriptor checks" =
  (module struct
    let int_as_text : int Db_type.t =
      Db_type.map
        Db_type.text
        ~encode:(fun value -> Ok (Int.to_string value))
        ~decode:(fun value ->
          match Int.of_string_opt value with
          | Some value -> Ok value
          | None -> Error "invalid encoded integer")
    ;;

    let text_as_int : string Db_type.t =
      Db_type.map
        Db_type.int
        ~encode:(fun value ->
          match Int.of_string_opt value with
          | Some value -> Ok value
          | None -> Error "invalid encoded integer")
        ~decode:(fun value -> Ok (Int.to_string value))
    ;;

    let wrong_int = Expr.constant int_as_text 1
    let wrong_text = Expr.constant text_as_int "1"

    let compile expression =
      Compiler.compile
        ~dialect:Dialect.portable
        Query.(from Item.table |> select (fun _ -> Projection.expr expression))
    ;;

    let rejected expression =
      match compile expression with
      | Error (Compile_error.Mismatched_sql_type _) -> true
      | _ -> false
    ;;

    let rejected_postgresql expression =
      match
        Compiler.compile
          ~dialect:Dialect.postgresql
          Query.(from Item.table |> select (fun _ -> Projection.expr expression))
      with
      | Error (Compile_error.Mismatched_sql_type _) -> true
      | _ -> false
    ;;

    let%test "arithmetic rejects nonnumeric descriptors with numeric OCaml values" =
      rejected Expr.Int.Infix.(wrong_int +. wrong_int)
    ;;

    let%test "arithmetic rejects different SQL numeric representations" =
      let as_bigint : int Db_type.t =
        Db_type.map
          Db_type.int64
          ~encode:(fun value -> Ok (Int64.of_int value))
          ~decode:(fun value ->
            match Int64.to_int value with
            | Some value -> Ok value
            | None -> Error "integer overflow")
      in
      rejected Expr.Int.Infix.(Expr.constant Db_type.int 1 +. Expr.constant as_bigint 2)
    ;;

    let%test "concatenation rejects nontext SQL descriptors" =
      rejected (Expr.concat wrong_text wrong_text)
    ;;

    let%test "LOWER checks the SQL input descriptor" = rejected (Expr.lower wrong_text)
    let%test "UPPER checks the SQL input descriptor" = rejected (Expr.upper wrong_text)
    let%test "LENGTH checks the SQL input descriptor" = rejected (Expr.length wrong_text)

    let%test "CAST checks the declared SQL source type" =
      rejected (Expr.cast_int_to_int64 wrong_int)
    ;;

    let%test "SUM checks its numeric SQL input" = rejected (Expr.sum_int wrong_int)

    let%test "AVG checks the source of its implicit CAST" =
      rejected (Expr.avg_int wrong_int)
    ;;

    let%test "concatenation checks the right descriptor too" =
      rejected (Expr.concat (Expr.constant Db_type.text "value") wrong_text)
    ;;

    let constant_as_text value =
      let descriptor =
        Db_type.map Db_type.text ~encode:(fun _ -> Ok "1") ~decode:(fun _ -> Ok value)
      in
      Expr.constant descriptor value
    ;;

    let%test "SUM float rejects text transport" =
      rejected (Expr.sum_float (constant_as_text 1.))
    ;;

    let%test "SUM bigint rejects text transport" =
      rejected_postgresql (Postgresql.Numeric.sum_int64 (constant_as_text 1L))
    ;;

    let%test "SUM numeric rejects text transport" =
      rejected_postgresql
        (Postgresql.Numeric.sum_numeric
           (constant_as_text (Decimal.of_string "1" |> Option.value_exn)))
    ;;

    let%test "exact AVG rejects a text descriptor" =
      rejected_postgresql (Postgresql.Numeric.avg_int wrong_int)
    ;;

    let%test "floating AVG rejects a text descriptor" =
      rejected (Expr.avg_float (constant_as_text 1.))
    ;;

    let%test "mapped codecs with the expected SQL representation remain usable" =
      let mapped = Db_type.map Db_type.int ~encode:Result.return ~decode:Result.return in
      Result.is_ok
        (compile Expr.Int.Infix.(Expr.constant mapped 1 +. Expr.constant Db_type.int 2))
    ;;

    let%test "smallint SUM still has a bigint result" =
      let smallint =
        Db_type.Postgresql.named
          ~schema:(Identifier.of_string_exn "pg_catalog")
          ~name:(Identifier.of_string_exn "int2")
          Db_type.int
      in
      Result.is_ok
        (Compiler.compile
           ~dialect:Dialect.postgresql
           Query.(
             from Item.table
             |> select (fun _ ->
               Projection.expr (Expr.sum_int (Expr.constant smallint 1)))))
    ;;
  end)
;;
