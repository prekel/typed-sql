open! Base
open Typed_sql
open Statement_compile
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "aggregate_items"
  let int_column = Column.v_exn table "int_value" Db_type.int
  let nullable_int_column = Column.nullable_v_exn table "nullable_int_value" Db_type.int
  let int64_column = Column.v_exn table "int64_value" Db_type.int64

  let nullable_int64_column =
    Column.nullable_v_exn table "nullable_int64_value" Db_type.int64
  ;;

  let float_column = Column.v_exn table "float_value" Db_type.float

  let nullable_float_column =
    Column.nullable_v_exn table "nullable_float_value" Db_type.float
  ;;

  let text_column = Column.v_exn table "text_value" Db_type.text
  let numeric_column = Column.v_exn table "numeric_value" Db_type.numeric

  let nullable_numeric_column =
    Column.nullable_v_exn table "nullable_numeric_value" Db_type.numeric
  ;;

  let int_value reference = Expr.column reference int_column
  let nullable_int_value reference = Expr.column reference nullable_int_column
  let int64_value reference = Expr.column reference int64_column
  let nullable_int64_value reference = Expr.column reference nullable_int64_column
  let float_value reference = Expr.column reference float_column
  let nullable_float_value reference = Expr.column reference nullable_float_column
  let text_value reference = Expr.column reference text_column
  let numeric_value reference = Expr.column reference numeric_column
  let nullable_numeric_value reference = Expr.column reference nullable_numeric_column
end

let compile_sql dialect query =
  Compiler.compile ~dialect query
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
  |> Compiled_query.sql
;;

let portable_aggregate =
  Query.Aggregate.(from Item.table)
  |> Query.aggregate_one (fun item ->
    Aggregate_projection.both
      (Aggregate_projection.sum_int (Item.int_value item))
      (Aggregate_projection.both
         (Aggregate_projection.sum_float (Item.float_value item))
         (Aggregate_projection.both
            (Aggregate_projection.min Db_type.Orderable.text (Item.text_value item))
            (Aggregate_projection.max Db_type.Orderable.text (Item.text_value item)))))
;;

let numeric_aggregate =
  Query.Aggregate.(from Item.table)
  |> Query.aggregate_one (fun item ->
    Aggregate_projection.both
      (Postgresql.Numeric_projection.sum_int64 (Item.int64_value item))
      (Aggregate_projection.both
         (Postgresql.Numeric_projection.sum_numeric (Item.numeric_value item))
         (Aggregate_projection.both
            (Postgresql.Numeric_projection.min_numeric (Item.numeric_value item))
            (Aggregate_projection.both
               (Postgresql.Numeric_projection.max_numeric (Item.numeric_value item))
               (Aggregate_projection.both
                  (Postgresql.Numeric_projection.sum_int64_nullable
                     (Item.nullable_int64_value item))
                  (Aggregate_projection.both
                     (Postgresql.Numeric_projection.sum_numeric_nullable
                        (Item.nullable_numeric_value item))
                     (Aggregate_projection.both
                        (Postgresql.Numeric_projection.min_numeric_nullable
                           (Item.nullable_numeric_value item))
                        (Postgresql.Numeric_projection.max_numeric_nullable
                           (Item.nullable_numeric_value item)))))))))
;;

let sqlite_numeric_aggregate =
  Query.Aggregate.(from Item.table)
  |> Query.aggregate_one (fun item ->
    Aggregate_projection.count (Item.numeric_value item))
;;

let%test_module "PostgreSQL string_agg" =
  (module struct
    module Item = struct
      type row

      let table : row Table.t = Table.v_exn "aggregate_items"
      let int_column = Column.v_exn table "int_value" Db_type.int
      let text_column = Column.v_exn table "text_value" Db_type.text

      let nullable_text_column =
        Column.nullable_v_exn table "nullable_text_value" Db_type.text
      ;;

      let int row = Expr.column row int_column
      let text row = Expr.column row text_column
      let nullable_text row = Expr.column row nullable_text_column
    end

    let%expect_test "renders its delimiter as a bind parameter" =
      Query.(
        from Item.table
        |> select_exactly_one (fun item ->
          Projection.expr
            (Postgresql.string_agg
               ~delimiter:(Expr.constant Db_type.text ", ")
               (Item.text item))))
      |> compile_sql Dialect.postgresql
      |> Stdlib.print_endline;
      [%expect
        {|
      SELECT
        STRING_AGG(
          t0."text_value",
          $1
        )
      FROM "aggregate_items" AS t0
      |}]
    ;;

    let%expect_test "orders values inside the aggregate" =
      Query.(
        from Item.table
        |> select_exactly_one (fun item ->
          Projection.expr
            (Postgresql.string_agg
               ~order_by:
                 [ Aggregate_order.desc
                     (let open Expr.Int.Infix in
                      Item.int item +. Expr.constant Db_type.int 1)
                 ]
               ~delimiter:(Expr.constant Db_type.text ",")
               (Item.text item))))
      |> compile_sql Dialect.postgresql
      |> Stdlib.print_endline;
      [%expect
        {|
      SELECT
        STRING_AGG(
          t0."text_value",
          $1
          ORDER BY (t0."int_value" + $2) DESC
        )
      FROM "aggregate_items" AS t0
      |}]
    ;;

    let%expect_test "accepts nullable text" =
      Query.(
        from Item.table
        |> select_exactly_one (fun item ->
          Projection.expr
            (Postgresql.string_agg_nullable
               ~delimiter:(Expr.constant Db_type.text ",")
               (Item.nullable_text item))))
      |> compile_sql Dialect.postgresql
      |> Stdlib.print_endline;
      [%expect
        {|
        SELECT
          STRING_AGG(
            t0."nullable_text_value",
            $1
          )
        FROM "aggregate_items" AS t0
        |}]
    ;;

    let%test "rejects nested string_agg calls" =
      let query =
        Query.(
          from Item.table
          |> select_exactly_one (fun item ->
            let inner =
              Postgresql.string_agg
                ~delimiter:(Expr.constant Db_type.text ",")
                (Item.text item)
            in
            Projection.expr
              (Postgresql.string_agg
                 ~delimiter:(Expr.constant Db_type.text ";")
                 (Expr.coalesce inner ~default:(Expr.constant Db_type.text "")))))
      in
      match Compiler.compile ~dialect:Dialect.postgresql query with
      | Error Compile_error.Nested_aggregate -> true
      | _ -> false
    ;;
  end)
;;

let%test "aggregate inside arithmetic retains exactly-one cardinality" =
  let query =
    Query.(
      from Item.table
      |> select_exactly_one (fun _ ->
        let open Expr.Int64.Infix in
        Projection.expr (Expr.count_all +. Expr.constant Db_type.int64 1L)))
  in
  Result.is_ok (Compiler.compile ~dialect:Dialect.postgresql query)
  && Result.is_ok (Compiler.compile ~dialect:Dialect.sqlite query)
;;

let%expect_test "portable scalar aggregates render in PostgreSQL" =
  Stdlib.print_endline (compile_sql Dialect.postgresql portable_aggregate);
  [%expect
    {|
    SELECT
      SUM(t0."int_value"),
      SUM(t0."float_value"),
      MIN(t0."text_value"),
      MAX(t0."text_value")
    FROM "aggregate_items" AS t0
    |}]
;;

let%expect_test "portable scalar aggregates render in SQLite" =
  Stdlib.print_endline (compile_sql Dialect.sqlite portable_aggregate);
  [%expect
    {|
    SELECT
      SUM(t0."int_value"),
      SUM(t0."float_value"),
      MIN(t0."text_value"),
      MAX(t0."text_value")
    FROM "aggregate_items" AS t0
    |}]
;;

let%expect_test "PostgreSQL numeric aggregates keep their exact SQL types" =
  Stdlib.print_endline (compile_sql Dialect.postgresql numeric_aggregate);
  [%expect
    {|
    SELECT
      SUM(t0."int64_value"),
      SUM(t0."numeric_value"),
      MIN(t0."numeric_value"),
      MAX(t0."numeric_value"),
      SUM(t0."nullable_int64_value"),
      SUM(t0."nullable_numeric_value"),
      MIN(t0."nullable_numeric_value"),
      MAX(t0."nullable_numeric_value")
    FROM "aggregate_items" AS t0
    |}]
;;

let%test_unit "PostgreSQL numeric aggregate rejects SQLite compilation" =
  match Compiler.compile ~dialect:Dialect.sqlite sqlite_numeric_aggregate with
  | Error error ->
    assert (
      String.equal
        (Compile_error.to_string error)
        "numeric is not supported by the sqlite dialect")
  | Ok _ -> failwith "PostgreSQL numeric aggregate unexpectedly compiled for SQLite"
;;

let%test_unit "numeric metadata remains exact and numeric multiset fields are rejected" =
  assert (String.equal (Db_type.name Db_type.numeric) "numeric");
  let query =
    Query.(
      from Item.table
      |> select_exactly_one (fun item ->
        Projection.multiset_agg (Projection.expr (Item.numeric_value item))))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error (Compile_error.Unsupported_multiset_field_type { path = [ 1 ]; type_name }) ->
    assert (String.equal type_name "numeric")
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "numeric multiset unexpectedly compiled"
;;

let%test_unit "SQLite rejects numeric values and runtime parameter slots" =
  let amount = Decimal.of_string "12.50" |> Option.value_exn in
  let query =
    Query.(
      from Item.table
      |> select (fun _ -> Projection.expr (Expr.constant Db_type.numeric amount)))
  in
  (match Compiler.compile ~dialect:Dialect.sqlite query with
   | Error _ -> ()
   | Ok _ -> failwith "numeric value unexpectedly compiled for SQLite");
  match
    Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map amount = params.expr Db_type.numeric ~get:Fn.id in
      params.query_many
        Query.(from Item.table |> select (fun _ -> Projection.expr amount)))
  with
  | exception Statement.Definition_error _ -> ()
  | _ -> failwith "SQLite accepted a numeric parameter slot"
;;

let%test_unit "SQLite rejects numeric values in RETURNING projections" =
  let returning =
    Insert.(
      into Item.table
      |> set Item.int_column 1
      |> returning (fun item -> Projection.expr (Item.numeric_value item)))
  in
  match Compiler.compile ~dialect:Dialect.sqlite returning with
  | Error _ -> ()
  | Ok _ -> failwith "SQLite unexpectedly compiled a numeric RETURNING projection"
;;

let%test_unit "nullable scalar aggregates and aggregate projection helpers compile" =
  let query =
    Query.Aggregate.(from Item.table)
    |> Query.aggregate_one (fun item ->
      let nullable_values =
        Aggregate_projection.both
          (Aggregate_projection.sum_int_nullable (Item.nullable_int_value item))
          (Aggregate_projection.both
             (Aggregate_projection.sum_float_nullable (Item.nullable_float_value item))
             (Aggregate_projection.both
                (Aggregate_projection.min_nullable
                   Db_type.Orderable.int
                   (Item.nullable_int_value item))
                (Aggregate_projection.max_nullable
                   Db_type.Orderable.int
                   (Item.nullable_int_value item))))
      in
      Aggregate_projection.map
        (Aggregate_projection.both
           (Aggregate_projection.count_distinct (Item.int_value item))
           nullable_values)
        ~f:Fn.id)
  in
  let sql = compile_sql Dialect.sqlite query in
  assert (String.is_substring sql ~substring:"COUNT(DISTINCT");
  assert (String.is_substring sql ~substring:"SUM(t0.\"nullable_int_value\")");
  assert (String.is_substring sql ~substring:"SUM(t0.\"nullable_float_value\")");
  assert (String.is_substring sql ~substring:"MIN(t0.\"nullable_int_value\")");
  assert (String.is_substring sql ~substring:"MAX(t0.\"nullable_int_value\")");
  let multiset_query =
    Query.Aggregate.(from Item.table)
    |> Query.aggregate_one (fun item ->
      Aggregate_projection.multiset_agg
        ~filter:(Item.int_value item >$ 0)
        ~order_by:[ Aggregate_order.asc (Item.text_value item) ]
        (Projection.expr (Item.int_value item)))
  in
  let multiset_sql = compile_sql Dialect.postgresql multiset_query in
  assert (String.is_substring multiset_sql ~substring:"JSONB_AGG");
  let sqlite_multiset_sql = compile_sql Dialect.sqlite multiset_query in
  assert (String.is_substring sqlite_multiset_sql ~substring:"FILTER");
  let query_api_multiset =
    Query.(
      from Item.table
      |> select_exactly_one (fun item ->
        Projection.multiset_agg
          ~filter:(Item.int_value item >$ 0)
          (Projection.expr (Item.int_value item))))
  in
  let query_api_sql = compile_sql Dialect.sqlite query_api_multiset in
  assert (String.is_substring query_api_sql ~substring:"FILTER")
;;

let check_scalar_subquery dialect scalar =
  let query =
    Query.(
      from Item.table |> select (fun _ -> Projection.expr (Expr.scalar_subquery scalar)))
  in
  ignore (compile_sql dialect query)
;;

let%test_unit "portable scalar aggregates prove their row bound" =
  check_scalar_subquery
    Dialect.sqlite
    Query.(from Item.table |> select_scalar (fun _ -> Expr.count_all));
  check_scalar_subquery
    Dialect.sqlite
    Query.(
      from Item.table
      |> select_scalar (fun item -> Expr.count_distinct (Item.int_value item)));
  check_scalar_subquery
    Dialect.sqlite
    Query.(
      from Item.table |> select_scalar (fun item -> Expr.sum_int (Item.int_value item)));
  check_scalar_subquery
    Dialect.sqlite
    Query.(
      from Item.table
      |> select_scalar (fun item -> Expr.sum_float (Item.float_value item)));
  check_scalar_subquery
    Dialect.sqlite
    Query.(
      from Item.table
      |> select_scalar (fun item -> Expr.min Db_type.Orderable.int (Item.int_value item)));
  check_scalar_subquery
    Dialect.sqlite
    Query.(
      from Item.table
      |> select_scalar (fun item -> Expr.max Db_type.Orderable.int (Item.int_value item)))
;;

let%test_unit "PostgreSQL numeric scalar aggregates prove their row bound" =
  check_scalar_subquery
    Dialect.postgresql
    Query.(
      from Item.table
      |> select_scalar (fun item -> Postgresql.Numeric.sum_int64 (Item.int64_value item)));
  check_scalar_subquery
    Dialect.postgresql
    Query.(
      from Item.table
      |> select_scalar (fun item ->
        Postgresql.Numeric.sum_numeric (Item.numeric_value item)));
  check_scalar_subquery
    Dialect.postgresql
    Query.(
      from Item.table
      |> select_scalar (fun item ->
        Postgresql.Numeric.min_numeric (Item.numeric_value item)));
  check_scalar_subquery
    Dialect.postgresql
    Query.(
      from Item.table
      |> select_scalar (fun item ->
        Postgresql.Numeric.max_numeric (Item.numeric_value item)))
;;

let traversal_condition item scalar_int exists_query =
  let value = Item.int_value item in
  let nullable_value = Item.nullable_int_value item in
  let open Condition.Infix in
  value
  =. Expr.constant Db_type.int 1
  &&. Expr.is_null nullable_value
  &&. Expr.is_not_null nullable_value
  &&. Expr.in_ value [ 1; 2 ]
  &&. Expr.not_in value [ 3; 4 ]
  &&. Expr.between value ~lower:0 ~upper:10
  &&. Query.in_subquery value scalar_int
  &&. Query.not_in_subquery value scalar_int
  &&. Query.exists exists_query
  &&. Query.not_exists exists_query
  ||. Condition.not_ (Expr.is_null nullable_value)
;;

let%test_unit "aggregate source analysis traverses multiset fields, filters and order" =
  let scalar_int =
    Query.(
      from Item.table |> limit_one |> select_scalar (fun item -> Item.int_value item))
  in
  let exists_query =
    Query.(from Item.table |> where (fun item -> Item.int_value item >$ 0))
  in
  let query =
    Query.(
      from Item.table
      |> select_exactly_one (fun item ->
        let value = Item.int_value item in
        let condition = traversal_condition item scalar_int exists_query in
        let case =
          Expr.case
            [ Condition.true_, value; Condition.false_, value; condition, value ]
            ~else_:(Expr.constant Db_type.int 0)
        in
        let nested_query =
          Query.(
            from Item.table
            |> select (fun nested -> Projection.expr (Item.int_value nested)))
        in
        let fields =
          Projection.both
            (Projection.expr case)
            (Projection.both
               (Projection.expr
                  (Expr.concat
                     (Expr.lower (Item.text_value item))
                     (Expr.upper (Item.text_value item))))
               (Projection.both
                  (Projection.expr (Expr.scalar_subquery scalar_int))
                  (Query.multiset nested_query)))
        in
        Projection.multiset_agg
          ~filter:condition
          ~order_by:
            [ Aggregate_order.asc
                (Expr.concat
                   (Expr.lower (Item.text_value item))
                   (Expr.upper (Item.text_value item)))
            ]
          fields))
  in
  let sql = compile_sql Dialect.postgresql query in
  assert (String.is_substring sql ~substring:"JSONB_AGG");
  assert (String.is_substring sql ~substring:"EXISTS")
;;

let%test_unit "exactly-one analysis traverses non-aggregate expressions and conditions" =
  let scalar_int =
    Query.(
      from Item.table |> limit_one |> select_scalar (fun item -> Item.int_value item))
  in
  let exists_query =
    Query.(from Item.table |> where (fun item -> Item.int_value item >$ 0))
  in
  let query =
    Query.(
      from Item.table
      |> select_exactly_one (fun item ->
        let value = Item.int_value item in
        let condition = traversal_condition item scalar_int exists_query in
        let nested_query =
          Query.(
            from Item.table
            |> select (fun nested -> Projection.expr (Item.int_value nested)))
        in
        let expressions =
          Projection.both
            (Projection.expr value)
            (Projection.expr
               (let open Expr.Int.Infix in
                value +. Expr.constant Db_type.int 1))
        in
        let expressions =
          Projection.both
            expressions
            (Projection.expr
               (Expr.concat
                  (Expr.lower (Item.text_value item))
                  (Expr.upper (Item.text_value item))))
        in
        let expressions =
          Projection.both
            expressions
            (Projection.expr (Expr.lower (Item.text_value item)))
        in
        let expressions =
          Projection.both expressions (Projection.expr Expr.current_timestamp)
        in
        let expressions =
          Projection.both expressions (Projection.expr (Expr.scalar_subquery scalar_int))
        in
        let expressions = Projection.both expressions (Query.multiset nested_query) in
        let expressions =
          Projection.both
            expressions
            (Projection.expr
               (Expr.case
                  [ Condition.true_, value; Condition.false_, value; condition, value ]
                  ~else_:(Expr.constant Db_type.int 0)))
        in
        expressions))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error Compile_error.Exactly_one_query_not_proven -> ()
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "non-aggregate query unexpectedly proved exactly one row"
;;
