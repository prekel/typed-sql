open! Base
open Typed_sql

let%test_module "shared assignments" =
  (module struct
    type row

    let items_table : row Table.t = Table.v_exn "assignment_items"
    let id = Column.v_exn items_table "id" Db_type.int64
    let note = Column.nullable_v_exn items_table "note" Db_type.text

    let assignments =
      Assignment.[ value id 1L; value_opt note (Some None); expr_opt id None ]
    ;;

    let%test_unit "one immutable list can feed all DML builders repeatedly" =
      let insert = Insert.(into items_table |> values assignments |> command) in
      let update = Update.(table items_table |> set assignments |> all_rows |> command) in
      let upsert =
        Insert.(
          into items_table
          |> values assignments
          |> on_conflict (Conflict_target.column id)
          |> do_update (fun ~existing:_ ~excluded:_ ->
            Conflict_update.(empty |> set assignments))
          |> command)
      in
      let merge =
        Merge.(
          into items_table
          |> using items_table ~f:(fun _ _ merge ->
            merge
            |> on Condition.true_
            |> when_matched_update assignments
            |> when_not_matched_insert assignments)
          |> command)
      in
      let sql command =
        Statement.command ~dialect:Dialect.postgresql command
        |> Statement.sql_exn ~dialect:Postgresql
      in
      List.iter [ insert; update; upsert; merge ] ~f:(fun command ->
        let first = sql command in
        assert (String.equal first (sql command)))
    ;;

    let foreign_table : row Table.t = Table.v_exn "foreign_items"
    let foreign_id = Column.v_exn foreign_table "id" Db_type.int64

    let rejects_foreign_assignment command =
      match Statement.command ~dialect:Dialect.portable command with
      | _ -> false
      | exception
          Statement.Definition_error
            { error = Compile_error.Invalid_assignment_source _; _ } -> true
    ;;

    let%test "INSERT rejects a foreign table descriptor with the same phantom type" =
      rejects_foreign_assignment
        Insert.(into items_table |> values Assignment.[ value foreign_id 1L ] |> command)
    ;;

    let%test "UPDATE rejects a foreign table descriptor with the same phantom type" =
      rejects_foreign_assignment
        Update.(
          table items_table
          |> set Assignment.[ value foreign_id 1L ]
          |> all_rows
          |> command)
    ;;

    let%test "nullable UPDATE rejects a foreign descriptor with the same phantom type" =
      rejects_foreign_assignment
        Update.(
          table items_table
          |> set_nullable_expr
               foreign_id
               (Expr.constant (Db_type.option Db_type.int64) None)
          |> all_rows
          |> command)
    ;;

    let%test_unit "omitted assignments do not introduce duplicate columns" =
      let statement =
        Statement.command
          ~dialect:Dialect.portable
          Insert.(
            into items_table
            |> values Assignment.[ value id 1L; value_opt id None; expr_opt id None ]
            |> values
                 Assignment.
                   [ note := Expr.constant (Db_type.option Db_type.text) (Some "note") ]
            |> command)
      in
      let sql = Statement.sql_exn ~dialect:Sqlite statement in
      assert (String.is_substring sql ~substring:"?2");
      assert (not (String.is_substring sql ~substring:"?3"))
    ;;

    let%test_unit "present optional expressions participate in duplicate checks" =
      let command =
        Insert.(
          into items_table
          |> values
               Assignment.
                 [ value id 1L; expr_opt id (Some (Expr.constant Db_type.int64 2L)) ]
          |> command)
      in
      match Statement.command ~dialect:Dialect.portable command with
      | _ -> failwith "duplicate optional assignment was accepted"
      | exception Statement.Definition_error _ -> ()
    ;;

    let%test_unit "omitting all assignments leaves an invalid empty row" =
      let command =
        Insert.(
          into items_table
          |> values Assignment.[ value_opt id None; expr_opt note None ]
          |> command)
      in
      match Statement.command ~dialect:Dialect.portable command with
      | _ -> failwith "empty row was accepted"
      | exception Statement.Definition_error _ -> ()
    ;;

    let%test_unit "runtime parameters can be used through the assignment operator" =
      let statement =
        Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
          let%map.Parameters input = params.column id ~get:Fn.id in
          params.command
            Insert.(into items_table |> values Assignment.[ id := input ] |> command))
      in
      let first = Statement.sql_exn ~dialect:Sqlite ~input:1L statement in
      let second = Statement.sql_exn ~dialect:Sqlite ~input:2L statement in
      assert (String.equal first second)
    ;;
  end)
;;
