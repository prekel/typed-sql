open! Base
open Typed_sql
open Infix

let ( let* ) = Lwt.bind

type error =
  | Check_violation
  | Database_error of string
  | Unexpected_error of string

type runner =
  { exec_sql : string -> unit Lwt.t
  ; run :
      'output.
      (unit, 'output, [ `Postgresql ]) Statement.t -> ('output, error) Result.t Lwt.t
  }

module Target = struct
  type row

  let table : row Table.t = Table.v_exn "merge_target"
  let id_column = Column.v_exn table "id" Db_type.int64
  let value_column = Column.v_exn table "value" Db_type.int64
  let id row = Expr.column row id_column
  let value row = Expr.column row value_column
  let projection row = Projection.pair (id row) (value row)
end

module Source = struct
  type row

  let table : row Table.t = Table.v_exn "merge_source"
  let id_column = Column.v_exn table "id" Db_type.int64
  let value_column = Column.v_exn table "value" Db_type.int64
  let action_column = Column.v_exn table "action" Db_type.text
  let id row = Expr.column row id_column
  let value row = Expr.column row value_column
  let action row = Expr.column row action_column
  let pair row = Projection.pair (id row) (value row)
  let projection row = Projection.both (pair row) (Projection.expr (action row))
end

module Audit = struct
  type row

  let table : row Table.t = Table.v_exn "merge_audit"
  let id_column = Column.v_exn table "id" Db_type.int64
  let id row = Expr.column row id_column
end

module Number = struct
  type row

  let table : row Table.t = Table.v_exn "merge_numbers"
  let value_column = Column.v_exn table "value" Db_type.int64
  let value row = Expr.column row value_column
  let projection row = Projection.expr (value row)
end

let error_to_string = function
  | Check_violation -> "unexpected check violation"
  | Database_error message | Unexpected_error message -> message
;;

let require runner statement =
  let* result = runner.run statement in
  match result with
  | Ok output -> Lwt.return output
  | Error error -> Lwt.fail_with (error_to_string error)
;;

let execute runner command =
  require runner (Statement.command ~dialect:Dialect.postgresql command)
;;

let fetch runner query =
  require runner (Statement.query_many ~dialect:Dialect.postgresql query)
;;

let target_rows =
  Query.(from Target.table |> order_by Target.id `Asc |> select Target.projection)
;;

let equal_pair (left_id, left_value) (right_id, right_value) =
  Int64.(left_id = right_id && left_value = right_value)
;;

let expect_rows runner expected =
  let* actual = fetch runner target_rows in
  if not (List.equal equal_pair actual expected) then
    failwith "MERGE produced unexpected target rows";
  Lwt.return_unit
;;

let expect_affected expected = function
  | Affected_rows.Known actual ->
    if not (Int.equal actual expected) then
      failwith "MERGE affected row count is wrong"
  | Unknown -> ()
;;

let reset runner = runner.exec_sql "TRUNCATE merge_target, merge_source, merge_audit"

let seed runner definitions =
  let* () = reset runner in
  Lwt_list.iter_s runner.exec_sql definitions
;;

let seed_upsert runner =
  seed
    runner
    [ "INSERT INTO merge_target VALUES (1, 10)"
    ; "INSERT INTO merge_source VALUES (1, 20, 'update'), (2, 30, 'insert')"
    ]
;;

let update_insert target source merge =
  Merge.(
    merge
    |> on (Target.id target =. Source.id source)
    |> when_matched_update
         Assignments.(empty |> set_expr Target.value_column (Source.value source))
    |> when_not_matched_insert
         Assignments.(
           empty
           |> set_expr Target.id_column (Source.id source)
           |> set_expr Target.value_column (Source.value source)))
;;

let merge_source () = Merge.(into Target.table |> using Source.table ~f:update_insert)

let test_update_insert runner =
  let* () = seed_upsert runner in
  let* affected = execute runner Merge.(merge_source () |> command) in
  expect_affected 2 affected;
  expect_rows runner [ 1L, 20L; 2L, 30L ]
;;

let test_ordered_actions runner =
  let* () =
    seed
      runner
      [ "INSERT INTO merge_target VALUES (1, 10), (2, 20), (3, 30)"
      ; "INSERT INTO merge_source VALUES (1, 11, 'delete'), (2, 22, 'keep'), (3, 33, 'update'), (4, 44, 'skip'), (5, 55, 'insert')"
      ]
  in
  let command =
    Merge.(
      into Target.table
      |> using Source.table ~f:(fun target source merge ->
        merge
        |> on (Target.id target =. Source.id source)
        |> when_matched_delete ~condition:(Source.action source =$ "delete")
        |> when_matched_do_nothing ~condition:(Source.action source =$ "keep")
        |> when_matched_update
             Assignments.(empty |> set_expr Target.value_column (Source.value source))
        |> when_not_matched_do_nothing ~condition:(Source.action source =$ "skip")
        |> when_not_matched_insert
             Assignments.(
               empty
               |> set_expr Target.id_column (Source.id source)
               |> set_expr Target.value_column (Source.value source)))
      |> command)
  in
  let* affected = execute runner command in
  expect_affected 3 affected;
  expect_rows runner [ 2L, 20L; 3L, 33L; 5L, 55L ]
;;

let test_empty_source runner =
  let* () = seed runner [ "INSERT INTO merge_target VALUES (1, 10)" ] in
  let* affected = execute runner Merge.(merge_source () |> command) in
  expect_affected 0 affected;
  expect_rows runner [ 1L, 10L ]
;;

let test_returning runner =
  let* () = seed_upsert runner in
  let query =
    Merge.(
      merge_source ()
      |> returning (fun target source ->
        Projection.both
          (Target.projection target)
          (Projection.expr (Source.action source))))
  in
  let* rows = fetch runner query in
  let rows =
    List.sort rows ~compare:(fun ((left, _), _) ((right, _), _) ->
      Int64.compare left right)
  in
  let equal ((left_id, left_value), left_action) ((right_id, right_value), right_action) =
    equal_pair (left_id, left_value) (right_id, right_value)
    && String.equal left_action right_action
  in
  if not (List.equal equal rows [ (1L, 20L), "update"; (2L, 30L), "insert" ]) then
    failwith "MERGE RETURNING did not expose target and source values";
  Lwt.return_unit
;;

let test_delete_returning runner =
  let* () =
    seed
      runner
      [ "INSERT INTO merge_target VALUES (1, 10)"
      ; "INSERT INTO merge_source VALUES (1, 99, 'delete')"
      ]
  in
  let query =
    Merge.(
      into Target.table
      |> using Source.table ~f:(fun target source merge ->
        merge |> on (Target.id target =. Source.id source) |> when_matched_delete)
      |> returning (fun target _ -> Target.projection target))
  in
  let* rows = fetch runner query in
  if not (List.equal equal_pair rows [ 1L, 10L ]) then
    failwith "MERGE DELETE RETURNING lost the deleted target row";
  expect_rows runner []
;;

let test_cte_source runner =
  let* () = seed_upsert runner in
  let relation =
    Derived_table.create
      ~table:Source.table
      ~columns:Source.projection
      Query.(from Source.table |> select Source.projection)
  in
  let command =
    Cte.with_command (Cte.select relation) ~f:(fun source ->
      Merge.(into Target.table |> using_cte source ~f:update_insert |> command))
  in
  let* _ = execute runner command in
  expect_rows runner [ 1L, 20L; 2L, 30L ]
;;

let test_modifying_cte_source runner =
  let* () = reset runner in
  let source =
    Postgresql.Cte.returning
      ~table:Source.table
      ~columns:Source.projection
      Insert.(
        into Source.table
        |> set Source.id_column 8L
        |> set Source.value_column 80L
        |> set Source.action_column "insert"
        |> returning Source.projection)
  in
  let command =
    Cte.with_command source ~f:(fun source ->
      Merge.(into Target.table |> using_cte source ~f:update_insert |> command))
  in
  let* _ = execute runner command in
  expect_rows runner [ 8L, 80L ]
;;

let test_merge_cte_returning runner =
  let* () = seed_upsert runner in
  let changed =
    Postgresql.Cte.returning
      ~table:Target.table
      ~columns:Target.projection
      Merge.(merge_source () |> returning (fun target _ -> Target.projection target))
  in
  let query =
    Cte.with_result changed ~f:(fun changed ->
      Query.(from_cte changed |> order_by Target.id `Asc |> select Target.projection))
  in
  let* rows = fetch runner query in
  if not (List.equal equal_pair rows [ 1L, 20L; 2L, 30L ]) then
    failwith "MERGE CTE did not expose its RETURNING rows";
  expect_rows runner [ 1L, 20L; 2L, 30L ]
;;

let test_merge_cte_command runner =
  let* () = seed_upsert runner in
  let query =
    Cte.with_result
      (Postgresql.Cte.command Merge.(merge_source () |> command))
      ~f:(fun () -> Query.select_one (Expr.constant Db_type.int64 7L))
  in
  let* rows = fetch runner query in
  if not (List.equal Int64.equal rows [ 7L ]) then
    failwith "side-effect-only MERGE CTE changed its consumer result";
  expect_rows runner [ 1L, 20L; 2L, 30L ]
;;

let test_values_source runner =
  let* () = reset runner in
  let values =
    Values.create
      ~table:Source.table
      ~columns:Source.pair
      ~first:
        Values.Row.(
          pair (Expr.constant Db_type.int64 1L) (Expr.constant Db_type.int64 10L))
      ~rest:
        [ Values.Row.(
            pair (Expr.constant Db_type.int64 2L) (Expr.constant Db_type.int64 20L))
        ]
  in
  let* _ =
    execute
      runner
      Merge.(into Target.table |> using_values values ~f:update_insert |> command)
  in
  expect_rows runner [ 1L, 10L; 2L, 20L ]
;;

let test_inferred_source runner =
  let* () = seed_upsert runner in
  let relation =
    Query.(
      from Source.table
      |> select_relation (fun source ->
        Derived_table.Fields.pair (Source.id source) (Source.value source)))
  in
  let command =
    Merge.(
      into Target.table
      |> using_relation relation ~f:(fun target (id, value) merge ->
        merge
        |> on (Target.id target =. id)
        |> when_matched_update Assignments.(empty |> set_expr Target.value_column value)
        |> when_not_matched_insert
             Assignments.(
               empty |> set_expr Target.id_column id |> set_expr Target.value_column value))
      |> command)
  in
  let* _ = execute runner command in
  expect_rows runner [ 1L, 20L; 2L, 30L ]
;;

let test_recursive_derived_source runner =
  let* () = reset runner in
  let relation query =
    Derived_table.create ~table:Number.table ~columns:Number.projection query
  in
  let numbers =
    Cte.recursive
      ~union:`Union_all
      ~anchor:(relation (Query.select_one (Expr.constant Db_type.int64 1L)))
      ~step:(fun numbers ->
        relation
          Query.(
            from_cte numbers
            |> where (fun number -> Number.value number <$ 3L)
            |> select (fun number ->
              let open Expr.Int64.Infix in
              Projection.expr (Number.value number +. Expr.constant Db_type.int64 1L))))
  in
  let source =
    relation
      (Cte.with_result numbers ~f:(fun numbers ->
         Query.(from_cte numbers |> select Number.projection)))
  in
  let command =
    Merge.(
      into Target.table
      |> using_derived source ~f:(fun target source merge ->
        merge
        |> on (Target.id target =. Number.value source)
        |> when_not_matched_insert
             Assignments.(
               empty
               |> set_expr Target.id_column (Number.value source)
               |> set Target.value_column 10L))
      |> command)
  in
  let* _ = execute runner command in
  expect_rows runner [ 1L, 10L; 2L, 10L; 3L, 10L ]
;;

let test_recursive_cte_input_and_merge_body runner =
  let* () = seed runner [ "INSERT INTO merge_source VALUES (1, 10, 'insert')" ] in
  let numbers =
    Cte.recursive_relation
      ~union:`Union_all
      ~anchor:
        Query.(
          from Source.table
          |> select_relation (fun source ->
            Derived_table.Fields.pair (Source.id source) (Source.value source)))
      ~step:(fun numbers ->
        Query.(
          from_cte_relation numbers
          |> where (fun (id, _) -> id <$ 3L)
          |> select_relation (fun (id, value) ->
            let open Expr.Int64.Infix in
            Derived_table.Fields.pair
              (id +. Expr.constant Db_type.int64 1L)
              (value +. Expr.constant Db_type.int64 10L))))
  in
  let query =
    Cte.with_result numbers ~f:(fun numbers ->
      let merged =
        Postgresql.Cte.returning
          ~table:Target.table
          ~columns:Target.projection
          Merge.(
            into Target.table
            |> using_cte_relation numbers ~f:(fun target (id, value) merge ->
              merge
              |> on (Target.id target =. id)
              |> when_not_matched_insert
                   Assignments.(
                     empty
                     |> set_expr Target.id_column id
                     |> set_expr Target.value_column value))
            |> returning (fun target _ -> Target.projection target))
      in
      Cte.with_result merged ~f:(fun changed ->
        Query.(from_cte changed |> order_by Target.id `Asc |> select Target.projection)))
  in
  let* rows = fetch runner query in
  if not (List.equal equal_pair rows [ 1L, 10L; 2L, 20L; 3L, 30L ]) then
    failwith "recursive SELECT CTE did not feed the MERGE CTE";
  expect_rows runner [ 1L, 10L; 2L, 20L; 3L, 30L ]
;;

let test_constraint_atomicity runner =
  let* () =
    seed
      runner
      [ "INSERT INTO merge_target VALUES (1, 10), (2, 20)"
      ; "INSERT INTO merge_source VALUES (1, 11, 'update'), (2, -1, 'update')"
      ]
  in
  let* result =
    runner.run
      (Statement.command ~dialect:Dialect.postgresql Merge.(merge_source () |> command))
  in
  (match result with
   | Error Check_violation -> ()
   | Error error -> failwith (error_to_string error)
   | Ok _ -> failwith "MERGE did not report its target check violation");
  expect_rows runner [ 1L, 10L; 2L, 20L ]
;;

let test_cardinality_atomicity runner =
  let* () =
    seed
      runner
      [ "INSERT INTO merge_target VALUES (1, 10), (2, 20)"
      ; "INSERT INTO merge_source VALUES (2, 22, 'update'), (1, 11, 'update'), (1, 12, 'update')"
      ]
  in
  let* result =
    runner.run
      (Statement.command ~dialect:Dialect.postgresql Merge.(merge_source () |> command))
  in
  (match result with
   | Error (Database_error message)
     when String.is_substring
            message
            ~substring:"MERGE command cannot affect row a second time" -> ()
   | Error error -> failwith (error_to_string error)
   | Ok _ -> failwith "MERGE did not reject duplicate modifications of one target row");
  expect_rows runner [ 1L, 10L; 2L, 20L ]
;;

let test_cte_atomicity runner =
  let* () =
    seed
      runner
      [ "INSERT INTO merge_target VALUES (1, 10), (2, 20)"
      ; "INSERT INTO merge_source VALUES (1, 11, 'update'), (2, -1, 'update')"
      ]
  in
  let audit =
    Postgresql.Cte.returning
      ~table:Audit.table
      ~columns:(fun row -> Projection.expr (Audit.id row))
      Insert.(
        into Audit.table
        |> set Audit.id_column 99L
        |> returning (fun row -> Projection.expr (Audit.id row)))
  in
  let command =
    Cte.with_command audit ~f:(fun audit ->
      let source =
        Derived_table.create
          ~table:Source.table
          ~columns:Source.projection
          Query.(
            from Source.table
            |> inner_join_cte audit ~on:(fun _ _ -> Condition.true_)
            |> select (fun (source, _) -> Source.projection source))
      in
      Merge.(into Target.table |> using_derived source ~f:update_insert |> command))
  in
  let* result = runner.run (Statement.command ~dialect:Dialect.postgresql command) in
  (match result with
   | Error Check_violation -> ()
   | Error error -> failwith (error_to_string error)
   | Ok _ -> failwith "MERGE with another modifying CTE unexpectedly succeeded");
  let* () = expect_rows runner [ 1L, 10L; 2L, 20L ] in
  let* audit_rows =
    fetch
      runner
      Query.(from Audit.table |> select (fun row -> Projection.expr (Audit.id row)))
  in
  if not (List.is_empty audit_rows) then
    failwith "MERGE failure did not roll back the preceding modifying CTE";
  Lwt.return_unit
;;

let run runner =
  let* () =
    Lwt_list.iter_s
      runner.exec_sql
      [ "CREATE TEMP TABLE merge_target (id BIGINT PRIMARY KEY, value BIGINT NOT NULL CHECK (value >= 0))"
      ; "CREATE TEMP TABLE merge_source (id BIGINT NOT NULL, value BIGINT NOT NULL, action TEXT NOT NULL)"
      ; "CREATE TEMP TABLE merge_audit (id BIGINT PRIMARY KEY)"
      ]
  in
  Lwt_list.iter_s
    (fun (name, test) ->
       Lwt.catch
         (fun () -> test runner)
         (fun error -> Lwt.fail_with (name ^ ": " ^ Exn.to_string error)))
    [ "update and insert", test_update_insert
    ; "ordered branches and every action", test_ordered_actions
    ; "empty source", test_empty_source
    ; "RETURNING target and source", test_returning
    ; "DELETE RETURNING", test_delete_returning
    ; "SELECT CTE source", test_cte_source
    ; "modifying CTE source", test_modifying_cte_source
    ; "MERGE CTE with RETURNING", test_merge_cte_returning
    ; "side-effect-only MERGE CTE", test_merge_cte_command
    ; "VALUES source", test_values_source
    ; "inferred source", test_inferred_source
    ; "recursive SELECT in derived source", test_recursive_derived_source
    ; "recursive SELECT feeding MERGE CTE", test_recursive_cte_input_and_merge_body
    ; "constraint failure atomicity", test_constraint_atomicity
    ; "cardinality failure atomicity", test_cardinality_atomicity
    ; "statement atomicity including modifying CTE", test_cte_atomicity
    ]
;;
