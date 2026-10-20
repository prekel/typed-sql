open! Base
open Typed_sql
open Statement_compile
open Infix

module Parent = struct
  type row

  let table : row Table.t = Table.v_exn "boundary_parent"
  let id = Column.v_exn table "id" Db_type.int64
  let value = Column.v_exn table "value" Db_type.int64
end

module Child = struct
  type row

  let table : row Table.t = Table.v_exn "boundary_child"
  let id = Column.v_exn table "id" Db_type.int64
  let parent_id = Column.v_exn table "parent_id" Db_type.int64
end

let correlated parent =
  Query.(
    from Child.table
    |> where (fun child ->
      Expr.column child Child.parent_id =. Expr.column parent Parent.id)
    |> limit_one
    |> select_scalar (fun child -> Expr.column child Child.id))
;;

let%test_module "DML correlation" =
  (module struct
    let delete =
      Delete.(
        from Parent.table
        |> where (fun parent ->
          Query.exists
            Query.(
              from Child.table
              |> where (fun child ->
                Expr.column child Child.parent_id =. Expr.column parent Parent.id)))
        |> command)
    ;;

    let returning =
      Update.(
        table Parent.table
        |> set Assignment.[ value Parent.value 7L ]
        |> all_rows
        |> returning (fun parent ->
          Projection.expr (Expr.scalar_subquery (correlated parent))))
    ;;

    let print_delete dialect =
      Compiler.compile_command ~dialect delete
      |> Result.map_error ~f:Compile_error.to_string
      |> Result.ok_or_failwith
      |> Compiled_command.sql
      |> Stdlib.print_endline
    ;;

    let print_returning dialect =
      Compiler.compile ~dialect returning
      |> Result.map_error ~f:Compile_error.to_string
      |> Result.ok_or_failwith
      |> Compiled_query.sql
      |> Stdlib.print_endline
    ;;

    let%expect_test "DELETE PostgreSQL" =
      print_delete Dialect.postgresql;
      [%expect
        {|
        DELETE FROM "boundary_parent" AS t0
        WHERE
          (EXISTS (
            SELECT
              1
            FROM "boundary_child" AS t1
            WHERE
              (t1."parent_id" = t0."id")
          ))
      |}]
    ;;

    let%expect_test "DELETE SQLite" =
      print_delete Dialect.sqlite;
      [%expect
        {|
        DELETE FROM "boundary_parent" AS t0
        WHERE
          (EXISTS (
            SELECT
              1
            FROM "boundary_child" AS t1
            WHERE
              (t1."parent_id" = t0."id")
          ))
      |}]
    ;;

    let%expect_test "RETURNING PostgreSQL" =
      print_returning Dialect.postgresql;
      [%expect
        {|
        UPDATE "boundary_parent" AS t0
        SET
          "value" = $1
        RETURNING
          (
            SELECT
              t1."id"
            FROM "boundary_child" AS t1
            WHERE
              (t1."parent_id" = t0."id")
            LIMIT $2
          )
      |}]
    ;;

    let%expect_test "RETURNING SQLite" =
      print_returning Dialect.sqlite;
      [%expect
        {|
        UPDATE "boundary_parent" AS t0
        SET
          "value" = ?1
        RETURNING
          (
            SELECT
              t1."id"
            FROM "boundary_child" AS t1
            WHERE
              (t1."parent_id" = "boundary_parent"."id")
            LIMIT ?2
          )
      |}]
    ;;
  end)
;;

let%test_module "grouped subquery correlations" =
  (module struct
    let rejected query =
      match Compiler.compile ~dialect:Dialect.postgresql query with
      | Error Compile_error.Ungrouped_expression -> true
      | _ -> false
    ;;

    let%test "scalar subquery rejects an ungrouped outer column" =
      rejected
        Query.(
          from Parent.table
          |> select (fun parent ->
            Projection.both
              (Projection.expr Expr.count_all)
              (Projection.expr (Expr.scalar_subquery (correlated parent)))))
    ;;

    let%test "EXISTS rejects an ungrouped outer column" =
      rejected
        Query.(
          from Parent.table
          |> select (fun parent ->
            Projection.both
              (Projection.expr Expr.count_all)
              (Projection.expr
                 (Query.exists_expr
                    Query.(
                      from Child.table
                      |> where (fun child ->
                        Expr.column child Child.parent_id =. Expr.column parent Parent.id))))))
    ;;

    let%test "multiset rejects an ungrouped outer column" =
      rejected
        Query.(
          from Parent.table
          |> select (fun parent ->
            Projection.both
              (Projection.expr Expr.count_all)
              (Query.multiset
                 Query.(
                   from Child.table
                   |> where (fun child ->
                     Expr.column child Child.parent_id =. Expr.column parent Parent.id)
                   |> select (fun child -> Projection.expr (Expr.column child Child.id))))))
    ;;

    let%test "grouped correlation permits inner-local columns" =
      Result.is_ok
        (Compiler.compile
           ~dialect:Dialect.postgresql
           Query.(
             from Parent.table
             |> group_by (fun parent -> Expr.column parent Parent.id)
             |> select (fun parent ->
               Projection.both
                 (Projection.expr Expr.count_all)
                 (Projection.expr (Expr.scalar_subquery (correlated parent))))))
    ;;
  end)
;;

let%test_module "recursive term restrictions" =
  (module struct
    let anchor = Query.select_one_relation (Expr.constant Db_type.int64 1L)

    let query step =
      let cte = Cte.recursive_relation ~union:`Union_all ~anchor ~step in
      Cte.with_result cte ~f:(fun self ->
        Query.(from_cte_relation self |> select Projection.expr))
    ;;

    let%test "aggregate recursive term is rejected" =
      match
        Compiler.compile
          ~dialect:Dialect.postgresql
          (query (fun self ->
             Query.(
               from_cte_relation self
               |> select_relation (fun _ -> Derived_table.Fields.expr Expr.count_all))))
      with
      | Error (Compile_error.Aggregate_not_allowed "recursive term") -> true
      | _ -> false
    ;;

    let%test "recursive reference on LEFT JOIN nullable side is rejected" =
      match
        Compiler.compile
          ~dialect:Dialect.postgresql
          (query (fun self ->
             Query.(
               from Parent.table
               |> left_join_cte_relation self ~on:(fun parent value ->
                 Expr.column parent Parent.id =. value)
               |> select_relation (fun (_, value) ->
                 Derived_table.Fields.expr
                   (Expr.coalesce value ~default:(Expr.constant Db_type.int64 0L))))))
      with
      | Error (Compile_error.Invalid_recursive_reference _) -> true
      | _ -> false
    ;;
  end)
;;

let%test "nested options are rejected before compilation" =
  match
    Compiler.compile
      ~dialect:Dialect.postgresql
      (Query.select_one
         (Expr.constant (Db_type.option (Db_type.option Db_type.int)) (Some None)))
  with
  | Error (Compile_error.Invalid_db_type _) -> true
  | _ -> false
;;

let%test "nested array codecs are rejected before compilation" =
  let typ = Db_type.Postgresql.array (Db_type.Postgresql.array Db_type.int) in
  let table : unit Table.t = Table.v_exn "nested_arrays" in
  let column = Column.v_exn table "value" typ in
  match
    Compiler.compile
      ~dialect:Dialect.postgresql
      Query.(from table |> select (fun row -> Projection.expr (Expr.column row column)))
  with
  | Error (Compile_error.Invalid_db_type _) -> true
  | _ -> false
;;

let%test_module "unrepresentable codec compositions" =
  (module struct
    let rejects typ =
      let table : unit Table.t = Table.v_exn "codec_boundary" in
      let column = Column.v_exn table "value" typ in
      match
        Compiler.compile
          ~dialect:Dialect.postgresql
          Query.(
            from table |> select (fun row -> Projection.expr (Expr.column row column)))
      with
      | Error (Compile_error.Invalid_db_type _) -> true
      | _ -> false
    ;;

    let%test "array rejects nullable scalar elements" =
      rejects (Db_type.Postgresql.array (Db_type.option Db_type.int))
    ;;

    let%test "array_list rejects nullable scalar elements" =
      rejects (Db_type.Postgresql.array_list (Db_type.option Db_type.int))
    ;;

    let%test "array_list rejects nested array elements" =
      rejects (Db_type.Postgresql.array_list (Db_type.Postgresql.array Db_type.int))
    ;;

    let%test "array rejects nullable nested array elements" =
      rejects
        (Db_type.Postgresql.array (Db_type.option (Db_type.Postgresql.array Db_type.int)))
    ;;

    let%expect_test "invalid codec diagnostics" =
      Stdlib.print_endline
        (Compile_error.to_string
           (Compile_error.Invalid_db_type
              "nested optional codecs cannot distinguish SQL NULL values"));
      [%expect
        {| invalid database codec: nested optional codecs cannot distinguish SQL NULL values |}]
    ;;
  end)
;;

let%test "outer aggregate in a scalar subquery belongs to the outer group" =
  Result.is_ok
    (Compiler.compile
       ~dialect:Dialect.postgresql
       Query.(
         from Parent.table
         |> select (fun parent ->
           Projection.expr
             (Expr.scalar_subquery_nullable
                Query.(
                  from Child.table
                  |> limit_one
                  |> select_scalar (fun _ ->
                    Expr.avg_int64 (Expr.column parent Parent.value)))))))
;;

let%test "mixed inner and outer aggregate inputs require the outer column to be grouped" =
  match
    Compiler.compile
      ~dialect:Dialect.postgresql
      Query.(
        from Parent.table
        |> select (fun parent ->
          Projection.both
            (Projection.expr Expr.count_all)
            (Projection.expr
               (Expr.scalar_subquery_nullable
                  Query.(
                    from Child.table
                    |> select_scalar (fun child ->
                      Expr.avg_int64
                        Expr.Int64.Infix.(
                          Expr.column child Child.id +. Expr.column parent Parent.value)))))))
  with
  | Error Compile_error.Ungrouped_expression -> true
  | _ -> false
;;

let%test "recursive ORDER BY aggregates are rejected" =
  let cte =
    Cte.recursive_relation
      ~union:`Union_all
      ~anchor:(Query.select_one_relation (Expr.constant Db_type.int64 1L))
      ~step:(fun self ->
        Query.(
          from_cte_relation self
          |> order_by (fun _ -> Expr.count_all) `Asc
          |> select_relation Derived_table.Fields.expr))
  in
  let query =
    Cte.with_result cte ~f:(fun self ->
      Query.(from_cte_relation self |> select Projection.expr))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error (Compile_error.Aggregate_not_allowed "recursive term") -> true
  | _ -> false
;;

let%test "recursive HAVING aggregates are rejected" =
  let cte =
    Cte.recursive_relation
      ~union:`Union_all
      ~anchor:(Query.select_one_relation (Expr.constant Db_type.int64 1L))
      ~step:(fun self ->
        Query.(
          from_cte_relation self
          |> group_by Fn.id
          |> having (fun _ -> Expr.count_all >. Expr.constant Db_type.int64 0L)
          |> select_relation Derived_table.Fields.expr))
  in
  let query =
    Cte.with_result cte ~f:(fun self ->
      Query.(from_cte_relation self |> select Projection.expr))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error (Compile_error.Aggregate_not_allowed "recursive term") -> true
  | _ -> false
;;

let%test "grouped correlation into a VALUES subquery is valid" =
  let table : unit Table.t = Table.v_exn "boundary_values" in
  let id = Column.v_exn table "id" Db_type.int64 in
  let values =
    Values.create
      ~table
      ~columns:(fun row -> Projection.expr (Expr.column row id))
      ~first:(Values.Row.expr (Expr.constant Db_type.int64 1L))
      ~rest:[]
  in
  Result.is_ok
    (Compiler.compile
       ~dialect:Dialect.postgresql
       Query.(
         from Parent.table
         |> group_by (fun parent -> Expr.column parent Parent.id)
         |> select (fun parent ->
           Projection.both
             (Projection.expr Expr.count_all)
             (Projection.expr
                (Expr.scalar_subquery
                   Query.(
                     from_values values
                     |> where (fun row ->
                       Expr.column row id =. Expr.column parent Parent.id)
                     |> limit_one
                     |> select_scalar (fun row -> Expr.column row id)))))))
;;

let%test "recursive reference on an INNER JOIN side is valid" =
  let cte =
    Cte.recursive_relation
      ~union:`Union_all
      ~anchor:(Query.select_one_relation (Expr.constant Db_type.int64 1L))
      ~step:(fun self ->
        Query.(
          from Parent.table
          |> inner_join_cte_relation self ~on:(fun parent value ->
            Expr.column parent Parent.id =. value)
          |> select_relation (fun (_, value) -> Derived_table.Fields.expr value)))
  in
  let query =
    Cte.with_result cte ~f:(fun self ->
      Query.(from_cte_relation self |> select Projection.expr))
  in
  Result.is_ok (Compiler.compile ~dialect:Dialect.postgresql query)
;;

let%expect_test "invalid codec S-expression" =
  Compile_error.sexp_of_t (Compile_error.Invalid_db_type "nested option")
  |> Sexp.to_string_hum
  |> Stdlib.print_endline;
  [%expect {| (Invalid_db_type "nested option") |}]
;;

let%test "nested array_list descriptors are rejected" =
  let typ = Db_type.Postgresql.array (Db_type.Postgresql.array_list Db_type.int) in
  let table : unit Table.t = Table.v_exn "nested_list_arrays" in
  let column = Column.v_exn table "value" typ in
  match
    Compiler.compile
      ~dialect:Dialect.postgresql
      Query.(from table |> select (fun row -> Projection.expr (Expr.column row column)))
  with
  | Error (Compile_error.Invalid_db_type _) -> true
  | _ -> false
;;

let%test_module "DELETE RETURNING correlation" =
  (module struct
    let query =
      Delete.(
        from Parent.table
        |> all_rows
        |> returning (fun parent ->
          Projection.expr (Expr.scalar_subquery (correlated parent))))
    ;;

    let print dialect =
      Compiler.compile ~dialect query
      |> Result.map_error ~f:Compile_error.to_string
      |> Result.ok_or_failwith
      |> Compiled_query.sql
      |> Stdlib.print_endline
    ;;

    let%expect_test "PostgreSQL" =
      print Dialect.postgresql;
      [%expect
        {|
        DELETE FROM "boundary_parent" AS t0
        RETURNING
          (
            SELECT
              t1."id"
            FROM "boundary_child" AS t1
            WHERE
              (t1."parent_id" = t0."id")
            LIMIT $1
          )
      |}]
    ;;

    let%expect_test "SQLite" =
      print Dialect.sqlite;
      [%expect
        {|
        DELETE FROM "boundary_parent" AS t0
        RETURNING
          (
            SELECT
              t1."id"
            FROM "boundary_child" AS t1
            WHERE
              (t1."parent_id" = "boundary_parent"."id")
            LIMIT ?1
          )
      |}]
    ;;
  end)
;;
