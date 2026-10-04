open! Base
open Typed_sql
open Statement_compile
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "ratings"
  let id = Column.v_exn table "id" Db_type.int
  let owner = Column.v_exn table "owner" Db_type.int
  let rating = Column.v_exn table "rating" Db_type.int
end

let sql dialect query =
  Compiler.compile ~dialect query
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
  |> Compiled_query.sql
;;

let averages =
  Query.(
    from Item.table
    |> select (fun row ->
      let i = Expr.column row Item.rating in
      Projection.both
        (Projection.expr (Expr.avg_int i))
        (Projection.both
           (Projection.expr (Expr.avg_int64 (Expr.cast_int_to_int64 i)))
           (Projection.expr (Expr.avg_float (Expr.cast_int_to_float i))))))
;;

let%expect_test "portable AVG PostgreSQL" =
  Stdlib.print_endline (sql Dialect.postgresql averages);
  [%expect
    {|
    SELECT
      AVG(CAST(t0."rating" AS double precision)),
      AVG(CAST(CAST(t0."rating" AS bigint) AS double precision)),
      AVG(CAST(t0."rating" AS double precision))
    FROM "ratings" AS t0
    |}]
;;

let%expect_test "portable AVG SQLite" =
  Stdlib.print_endline (sql Dialect.sqlite averages);
  [%expect
    {|
    SELECT
      AVG(CAST(t0."rating" AS REAL)),
      AVG(CAST(CAST(t0."rating" AS INTEGER) AS REAL)),
      AVG(CAST(t0."rating" AS REAL))
    FROM "ratings" AS t0
    |}]
;;

let update () =
  Update.(
    table Item.table
    |> with_target ~f:(fun target update ->
      let average =
        Query.(
          from Item.table
          |> where (fun row -> Expr.column row Item.owner =. Expr.column target Item.id)
          |> select_scalar (fun row -> Expr.avg_int (Expr.column row Item.rating)))
      in
      update
      |> set_nullable_expr
           Item.rating
           (Expr.cast_float_to_int_nullable (Expr.scalar_subquery_nullable average)))
    |> all_rows
    |> command)
;;

let command_sql dialect =
  Compiler.compile_command ~dialect (update ())
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
  |> Compiled_command.sql
;;

let%expect_test "correlated AVG UPDATE PostgreSQL" =
  Stdlib.print_endline (command_sql Dialect.postgresql);
  [%expect
    {|
    UPDATE "ratings" AS t0
    SET
      "rating" = CAST((
        SELECT
          AVG(CAST(t1."rating" AS double precision))
        FROM "ratings" AS t1
        WHERE
          (t1."owner" = t0."id")
      ) AS integer)
    |}]
;;

let%expect_test "correlated AVG UPDATE SQLite" =
  Stdlib.print_endline (command_sql Dialect.sqlite);
  [%expect
    {|
    UPDATE "ratings" AS t0
    SET
      "rating" = CAST((
        SELECT
          AVG(CAST(t1."rating" AS REAL))
        FROM "ratings" AS t1
        WHERE
          (t1."owner" = t0."id")
      ) AS INTEGER)
    |}]
;;

let%test_unit "CAST retains foreign-source validation" =
  let escaped = ref None in
  ignore
    Query.(
      from Item.table
      |> select (fun row ->
        escaped := Some row;
        Projection.expr (Expr.column row Item.rating)));
  let query =
    Query.(
      from Item.table
      |> select (fun _ ->
        Projection.expr
          (Expr.cast_int_to_float (Expr.column (Option.value_exn !escaped) Item.rating))))
  in
  match Compiler.compile ~dialect:Dialect.sqlite query with
  | Error (Foreign_source _) -> ()
  | _ -> failwith "CAST hid a foreign source"
;;

let%test_unit "CAST retains nested-aggregate validation" =
  let query =
    Query.(
      from Item.table
      |> select (fun row ->
        Projection.expr
          (Expr.avg_float_nullable
             (Expr.cast_int64_to_float_nullable
                (Expr.sum_int (Expr.column row Item.rating))))))
  in
  assert (Result.is_error (Compiler.compile ~dialect:Dialect.sqlite query))
;;

let%test_unit "AVG under CAST proves scalar cardinality" =
  let scalar =
    Query.(
      from Item.table
      |> select_scalar (fun row ->
        Expr.cast_float_to_int_nullable (Expr.avg_int (Expr.column row Item.rating))))
  in
  let query =
    Query.(
      from Item.table
      |> select (fun _ -> Projection.expr (Expr.scalar_subquery_nullable scalar)))
  in
  assert (Result.is_ok (Compiler.compile ~dialect:Dialect.sqlite query))
;;

let unit_expr expression = Projection.map (Projection.expr expression) ~f:(fun _ -> ())

let combine expressions =
  List.reduce_exn expressions ~f:(fun a b ->
    Projection.map (Projection.both a b) ~f:(fun _ -> ()))
;;

let portable_casts value =
  let i = Expr.constant Db_type.int value in
  let i64 = Expr.constant Db_type.int64 (Int64.of_int value) in
  let f = Expr.constant Db_type.float (Float.of_int value) in
  combine
    [ unit_expr (Expr.cast_int_to_int64 i)
    ; unit_expr (Expr.cast_int_to_int64_nullable (Expr.to_nullable i))
    ; unit_expr (Expr.cast_int_to_float i)
    ; unit_expr (Expr.cast_int_to_float_nullable (Expr.to_nullable i))
    ; unit_expr (Expr.cast_int64_to_int i64)
    ; unit_expr (Expr.cast_int64_to_int_nullable (Expr.to_nullable i64))
    ; unit_expr (Expr.cast_int64_to_float i64)
    ; unit_expr (Expr.cast_int64_to_float_nullable (Expr.to_nullable i64))
    ; unit_expr (Expr.cast_float_to_int f)
    ; unit_expr (Expr.cast_float_to_int_nullable (Expr.to_nullable f))
    ; unit_expr (Expr.cast_float_to_int64 f)
    ; unit_expr (Expr.cast_float_to_int64_nullable (Expr.to_nullable f))
    ]
;;

let%expect_test "portable casts postgresql" =
  let query = Query.(from Item.table |> select (fun _ -> portable_casts 7)) in
  Stdlib.print_endline (sql Dialect.postgresql query);
  [%expect
    {|
    SELECT
      CAST($1 AS bigint),
      CAST($2 AS bigint),
      CAST($3 AS double precision),
      CAST($4 AS double precision),
      CAST($5 AS integer),
      CAST($6 AS integer),
      CAST($7 AS double precision),
      CAST($8 AS double precision),
      CAST($9 AS integer),
      CAST($10 AS integer),
      CAST($11 AS bigint),
      CAST($12 AS bigint)
    FROM "ratings" AS t0
    |}]
;;

let%expect_test "portable casts sqlite" =
  let query = Query.(from Item.table |> select (fun _ -> portable_casts 7)) in
  Stdlib.print_endline (sql Dialect.sqlite query);
  [%expect
    {|
    SELECT
      CAST(?1 AS INTEGER),
      CAST(?2 AS INTEGER),
      CAST(?3 AS REAL),
      CAST(?4 AS REAL),
      CAST(?5 AS INTEGER),
      CAST(?6 AS INTEGER),
      CAST(?7 AS REAL),
      CAST(?8 AS REAL),
      CAST(?9 AS INTEGER),
      CAST(?10 AS INTEGER),
      CAST(?11 AS INTEGER),
      CAST(?12 AS INTEGER)
    FROM "ratings" AS t0
    |}]
;;

let%test_unit "portable casts have stable parameterized SQL" =
  let query value = Query.(from Item.table |> select (fun _ -> portable_casts value)) in
  assert (
    String.equal (sql Dialect.postgresql (query 1)) (sql Dialect.postgresql (query 9)))
;;

let numeric_casts value =
  let i = Expr.constant Db_type.int value in
  let i64 = Expr.constant Db_type.int64 (Int64.of_int value) in
  let f = Expr.constant Db_type.float (Float.of_int value) in
  let n =
    Expr.constant
      Db_type.numeric
      (Decimal.of_string (Int.to_string value) |> Option.value_exn)
  in
  combine
    [ unit_expr (Postgresql.Numeric.cast_int_to_numeric i)
    ; unit_expr (Postgresql.Numeric.cast_int_to_numeric_nullable (Expr.to_nullable i))
    ; unit_expr (Postgresql.Numeric.cast_int64_to_numeric i64)
    ; unit_expr (Postgresql.Numeric.cast_int64_to_numeric_nullable (Expr.to_nullable i64))
    ; unit_expr (Postgresql.Numeric.cast_float_to_numeric f)
    ; unit_expr (Postgresql.Numeric.cast_float_to_numeric_nullable (Expr.to_nullable f))
    ; unit_expr (Postgresql.Numeric.cast_numeric_to_int n)
    ; unit_expr (Postgresql.Numeric.cast_numeric_to_int_nullable (Expr.to_nullable n))
    ; unit_expr (Postgresql.Numeric.cast_numeric_to_int64 n)
    ; unit_expr (Postgresql.Numeric.cast_numeric_to_int64_nullable (Expr.to_nullable n))
    ; unit_expr (Postgresql.Numeric.cast_numeric_to_float n)
    ; unit_expr (Postgresql.Numeric.cast_numeric_to_float_nullable (Expr.to_nullable n))
    ]
;;

let%expect_test "numeric casts postgresql" =
  let query = Query.(from Item.table |> select (fun _ -> numeric_casts 7)) in
  Stdlib.print_endline (sql Dialect.postgresql query);
  [%expect
    {|
    SELECT
      CAST($1 AS numeric),
      CAST($2 AS numeric),
      CAST($3 AS numeric),
      CAST($4 AS numeric),
      CAST($5 AS numeric),
      CAST($6 AS numeric),
      CAST($7 AS integer),
      CAST($8 AS integer),
      CAST($9 AS bigint),
      CAST($10 AS bigint),
      CAST($11 AS double precision),
      CAST($12 AS double precision)
    FROM "ratings" AS t0
    |}]
;;

let%test_unit "numeric casts have stable parameterized SQL" =
  let query value = Query.(from Item.table |> select (fun _ -> numeric_casts value)) in
  assert (
    String.equal (sql Dialect.postgresql (query 1)) (sql Dialect.postgresql (query 9)))
;;

let%test_unit "portable AVG projections, including nullable inputs" =
  let query =
    Query.Aggregate.(from Item.table)
    |> Query.aggregate_one (fun row ->
      let i = Expr.column row Item.rating in
      let i64 = Expr.cast_int_to_int64 i in
      let f = Expr.cast_int_to_float i in
      List.reduce_exn
        [ Aggregate_projection.map (Aggregate_projection.avg_int i) ~f:(fun _ -> ())
        ; Aggregate_projection.map
            (Aggregate_projection.avg_int_nullable (Expr.to_nullable i))
            ~f:(fun _ -> ())
        ; Aggregate_projection.map (Aggregate_projection.avg_int64 i64) ~f:(fun _ -> ())
        ; Aggregate_projection.map
            (Aggregate_projection.avg_int64_nullable (Expr.to_nullable i64))
            ~f:(fun _ -> ())
        ; Aggregate_projection.map (Aggregate_projection.avg_float f) ~f:(fun _ -> ())
        ; Aggregate_projection.map
            (Aggregate_projection.avg_float_nullable (Expr.to_nullable f))
            ~f:(fun _ -> ())
        ]
        ~f:(fun a b ->
          Aggregate_projection.map (Aggregate_projection.both a b) ~f:(fun _ -> ())))
  in
  assert (Result.is_ok (Compiler.compile ~dialect:Dialect.sqlite query))
;;

let%test_unit "exact AVG projections, including nullable inputs" =
  let query =
    Query.Aggregate.(from Item.table)
    |> Query.aggregate_one (fun row ->
      let i = Expr.column row Item.rating in
      let i64 = Expr.cast_int_to_int64 i in
      let n = Postgresql.Numeric.cast_int_to_numeric i in
      List.reduce_exn
        [ Aggregate_projection.map (Postgresql.Numeric_projection.avg_int i) ~f:(fun _ ->
            ())
        ; Aggregate_projection.map
            (Postgresql.Numeric_projection.avg_int_nullable (Expr.to_nullable i))
            ~f:(fun _ -> ())
        ; Aggregate_projection.map
            (Postgresql.Numeric_projection.avg_int64 i64)
            ~f:(fun _ -> ())
        ; Aggregate_projection.map
            (Postgresql.Numeric_projection.avg_int64_nullable (Expr.to_nullable i64))
            ~f:(fun _ -> ())
        ; Aggregate_projection.map
            (Postgresql.Numeric_projection.avg_numeric n)
            ~f:(fun _ -> ())
        ; Aggregate_projection.map
            (Postgresql.Numeric_projection.avg_numeric_nullable (Expr.to_nullable n))
            ~f:(fun _ -> ())
        ]
        ~f:(fun a b ->
          Aggregate_projection.map (Aggregate_projection.both a b) ~f:(fun _ -> ())))
  in
  assert (Result.is_ok (Compiler.compile ~dialect:Dialect.postgresql query))
;;

let%expect_test "native numeric AVG PostgreSQL" =
  let query =
    Query.(
      from Item.table
      |> select (fun row ->
        let i = Expr.column row Item.rating in
        let i64 = Expr.cast_int_to_int64 i in
        let n = Postgresql.Numeric.cast_int_to_numeric i in
        combine
          [ unit_expr (Postgresql.Numeric.avg_int i)
          ; unit_expr (Postgresql.Numeric.avg_int_nullable (Expr.to_nullable i))
          ; unit_expr (Postgresql.Numeric.avg_int64 i64)
          ; unit_expr (Postgresql.Numeric.avg_int64_nullable (Expr.to_nullable i64))
          ; unit_expr (Postgresql.Numeric.avg_numeric n)
          ; unit_expr (Postgresql.Numeric.avg_numeric_nullable (Expr.to_nullable n))
          ]))
  in
  Stdlib.print_endline (sql Dialect.postgresql query);
  [%expect
    {|
    SELECT
      AVG(t0."rating"),
      AVG(t0."rating"),
      AVG(CAST(t0."rating" AS bigint)),
      AVG(CAST(t0."rating" AS bigint)),
      AVG(CAST(t0."rating" AS numeric)),
      AVG(CAST(t0."rating" AS numeric))
    FROM "ratings" AS t0
    |}]
;;

let%test_unit "CAST remains visible to grouping validation" =
  let query =
    Query.(
      from Item.table
      |> select (fun row ->
        Projection.both
          (Projection.expr (Expr.cast_int_to_float (Expr.column row Item.rating)))
          (Projection.expr Expr.count_all)))
  in
  match Compiler.compile ~dialect:Dialect.sqlite query with
  | Error Ungrouped_expression -> ()
  | _ -> failwith "CAST hid an ungrouped column"
;;

let%test_unit "grouped CAST compares numeric source and target types" =
  let make cast =
    Query.(
      from Item.table
      |> group_by (fun row -> Expr.cast_int_to_float (Expr.column row Item.rating))
      |> select (fun row -> Projection.expr (cast (Expr.column row Item.rating))))
  in
  assert (
    Result.is_ok
      (Compiler.compile ~dialect:Dialect.postgresql (make Expr.cast_int_to_float)));
  assert (
    Result.is_error
      (Compiler.compile ~dialect:Dialect.postgresql (make Expr.cast_int_to_int64)))
;;

let%test_module "correlated UPDATE alias scope" =
  (module struct
    let scalar target =
      Query.(
        from Item.table
        |> where (fun row -> Expr.column row Item.id =. Expr.column target Item.id)
        |> limit_one
        |> select_scalar (fun row -> Expr.column row Item.rating))
    ;;

    let nullable target = Expr.scalar_subquery (scalar target)

    let value target =
      Expr.coalesce (nullable target) ~default:(Expr.constant Db_type.int 0)
    ;;

    let plain = Expr.constant Db_type.int 1
    let nullable_plain = Expr.to_nullable plain

    let check_expr make =
      let command =
        Update.(
          table Item.table
          |> with_target ~f:(fun target update ->
            update |> set_expr Item.rating (make target))
          |> all_rows
          |> command)
      in
      let compiled =
        Compiler.compile_command ~dialect:Dialect.sqlite command
        |> Result.map_error ~f:Compile_error.to_string
        |> Result.ok_or_failwith
      in
      assert (
        String.is_substring
          (Compiled_command.sql compiled)
          ~substring:"UPDATE \"ratings\" AS t0")
    ;;

    let check_condition make =
      let command =
        Update.(
          table Item.table
          |> set Item.rating 1
          |> with_target ~f:(fun target update -> update |> where (fun _ -> make target))
          |> command)
      in
      let compiled =
        Compiler.compile_command ~dialect:Dialect.sqlite command
        |> Result.map_error ~f:Compile_error.to_string
        |> Result.ok_or_failwith
      in
      assert (
        String.is_substring
          (Compiled_command.sql compiled)
          ~substring:"UPDATE \"ratings\" AS t0")
    ;;

    let%test_unit "alias survives arithmetic left" =
      check_expr (fun target -> Expr.Int.Infix.(value target +. plain))
    ;;

    let%test_unit "alias survives arithmetic right" =
      check_expr (fun target -> Expr.Int.Infix.(plain +. value target))
    ;;

    let%test_unit "alias survives CASE fallback" =
      check_expr (fun target ->
        Expr.case [ Expr.column target Item.id =$ 1, plain ] ~else_:(value target))
    ;;

    let%test_unit "alias survives CASE predicate" =
      check_expr (fun target ->
        Expr.case [ Expr.is_null (nullable target), plain ] ~else_:plain)
    ;;

    let%test_unit "alias survives CASE branch" =
      check_expr (fun target ->
        Expr.case [ Expr.column target Item.id =$ 1, value target ] ~else_:plain)
    ;;

    let%test_unit "alias survives nullable fallback" =
      check_expr (fun target ->
        Expr.coalesce
          (Expr.constant (Db_type.option Db_type.int) None)
          ~default:(value target))
    ;;

    let%test_unit "alias survives string unary" =
      check_expr (fun target ->
        Expr.length
          (Expr.lower
             (Expr.coalesce
                (Expr.scalar_subquery
                   Query.(
                     from Item.table
                     |> where (fun row ->
                       Expr.column row Item.id =. Expr.column target Item.id)
                     |> limit_one
                     |> select_scalar (fun _ -> Expr.constant Db_type.text "text")))
                ~default:(Expr.constant Db_type.text ""))))
    ;;

    let%test_unit "alias survives string concat" =
      check_expr (fun target ->
        Expr.length
          (Expr.concat
             (Expr.constant Db_type.text "prefix")
             (Expr.coalesce
                (Expr.scalar_subquery
                   Query.(
                     from Item.table
                     |> where (fun row ->
                       Expr.column row Item.id =. Expr.column target Item.id)
                     |> limit_one
                     |> select_scalar (fun _ -> Expr.constant Db_type.text "text")))
                ~default:(Expr.constant Db_type.text ""))))
    ;;

    let%test_unit "alias survives EXISTS expression" =
      check_expr (fun target ->
        Expr.case
          [ ( Query.exists_expr
                Query.(
                  from Item.table
                  |> where (fun row ->
                    Expr.column row Item.id =. Expr.column target Item.id))
              =$ true
            , plain )
          ]
          ~else_:plain)
    ;;

    let%test_unit "alias survives comparison left" =
      check_condition (fun target -> nullable target =. nullable_plain)
    ;;

    let%test_unit "alias survives comparison right" =
      check_condition (fun target -> nullable_plain =. nullable target)
    ;;

    let%test_unit "alias survives null predicate" =
      check_condition (fun target -> Expr.is_null (nullable target))
    ;;

    let%test_unit "alias survives nonnull predicate" =
      check_condition (fun target -> Expr.is_not_null (nullable target))
    ;;

    let%test_unit "alias survives membership value" =
      check_condition (fun target -> Expr.in_exprs (nullable target) [ nullable_plain ])
    ;;

    let%test_unit "alias survives membership list" =
      check_condition (fun target -> Expr.in_exprs nullable_plain [ nullable target ])
    ;;

    let%test_unit "alias survives nonmembership value" =
      check_condition (fun target ->
        Expr.not_in_exprs (nullable target) [ nullable_plain ])
    ;;

    let%test_unit "alias survives nonmembership list" =
      check_condition (fun target -> Expr.not_in_exprs nullable_plain [ nullable target ])
    ;;

    let%test_unit "alias survives range value" =
      check_condition (fun target ->
        Expr.between_exprs (nullable target) ~lower:nullable_plain ~upper:nullable_plain)
    ;;

    let%test_unit "alias survives range lower" =
      check_condition (fun target ->
        Expr.between_exprs nullable_plain ~lower:(nullable target) ~upper:nullable_plain)
    ;;

    let%test_unit "alias survives range upper" =
      check_condition (fun target ->
        Expr.between_exprs nullable_plain ~lower:nullable_plain ~upper:(nullable target))
    ;;

    let%test_unit "alias survives conjunction" =
      check_condition (fun target ->
        Expr.column target Item.id =$ 1 &&. Expr.is_null (nullable target))
    ;;

    let%test_unit "alias survives disjunction" =
      check_condition (fun target ->
        Expr.column target Item.id =$ 1 ||. Expr.is_null (nullable target))
    ;;

    let%test_unit "alias survives negation" =
      check_condition (fun target -> Condition.not_ (Expr.is_null (nullable target)))
    ;;

    let%test_unit "alias survives exists" =
      check_condition (fun target ->
        Query.exists
          Query.(
            from Item.table
            |> where (fun row -> Expr.column row Item.id =. Expr.column target Item.id)))
    ;;

    let%test_unit "alias survives not exists" =
      check_condition (fun target ->
        Query.not_exists
          Query.(
            from Item.table
            |> where (fun row -> Expr.column row Item.id =. Expr.column target Item.id)))
    ;;

    let%test_unit "alias survives in subquery" =
      check_condition (fun target -> Query.in_subquery plain (scalar target))
    ;;

    let%test_unit "alias survives not in subquery" =
      check_condition (fun target -> Query.not_in_subquery plain (scalar target))
    ;;
  end)
;;

let%test_module "grouped numeric casts" =
  (module struct
    let check cast =
      let query =
        Query.(
          from Item.table
          |> group_by (fun _ -> cast ())
          |> select (fun _ ->
            Projection.both (Projection.expr (cast ())) (Projection.expr Expr.count_all)))
      in
      assert (Result.is_ok (Compiler.compile ~dialect:Dialect.postgresql query))
    ;;

    let%test_unit "int64 input and integer target" =
      check (fun () -> Expr.cast_int64_to_int (Expr.constant Db_type.int64 1L))
    ;;

    let%test_unit "bigint target" =
      check (fun () -> Expr.cast_int_to_int64 (Expr.constant Db_type.int 1))
    ;;

    let%test_unit "numeric input and floating target" =
      let n = Expr.constant Db_type.numeric (Option.value_exn (Decimal.of_string "1")) in
      check (fun () -> Postgresql.Numeric.cast_numeric_to_float n)
    ;;

    let%test_unit "numeric target" =
      check (fun () ->
        Postgresql.Numeric.cast_int_to_numeric (Expr.constant Db_type.int 1))
    ;;
  end)
;;

let%test_unit "outer-only AVG cannot prove inner scalar cardinality" =
  let query =
    Query.(
      from Item.table
      |> select (fun outer ->
        let scalar =
          Query.(
            from Item.table
            |> select_scalar (fun _ -> Expr.avg_int (Expr.column outer Item.rating)))
        in
        Projection.expr (Expr.scalar_subquery_nullable scalar)))
  in
  assert (Result.is_error (Compiler.compile ~dialect:Dialect.postgresql query))
;;

let%test_unit "with_target preserves the immutable row scope" =
  let original =
    Update.(
      table Item.table
      |> set Item.rating 7
      |> where (fun row -> Expr.column row Item.id =$ 1))
  in
  let changed =
    Update.(
      original
      |> with_target ~f:(fun target update ->
        update |> where (fun _ -> Expr.column target Item.rating =$ 9))
      |> command)
  in
  let original = Update.(original |> command) in
  let render command =
    Compiler.compile_command ~dialect:Dialect.sqlite command
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> Compiled_command.sql
  in
  assert (not (String.equal (render original) (render changed)))
;;

let%test_unit "AVG retains exactly-one cardinality with FETCH WITH TIES" =
  let average row = Expr.avg_int (Expr.column row Item.rating) in
  let query =
    Query.(
      from Item.table
      |> order_by average `Asc
      |> Postgresql.Query.fetch_with_ties 1
      |> select_exactly_one (fun row -> Projection.expr (average row)))
  in
  let statement = Statement.query_one ~dialect:Dialect.postgresql query in
  assert (
    String.is_substring
      (Statement.sql_exn ~dialect:Postgresql ~input:() statement)
      ~substring:"FETCH FIRST 1 ROWS WITH TIES")
;;

let%test_unit "AVG in a range bound proves exactly-one cardinality under CASE" =
  let query =
    Query.(
      from Item.table
      |> select_exactly_one (fun row ->
        let average = Expr.avg_int (Expr.column row Item.rating) in
        let condition =
          Expr.between_exprs
            (Expr.constant (Db_type.option Db_type.float) (Some 3.))
            ~lower:average
            ~upper:(Expr.constant (Db_type.option Db_type.float) (Some 4.))
        in
        Projection.expr
          (Expr.case
             [ condition, Expr.constant Db_type.int 1 ]
             ~else_:(Expr.constant Db_type.int 0))))
  in
  ignore (Statement.query_one ~dialect:Dialect.sqlite query)
;;
