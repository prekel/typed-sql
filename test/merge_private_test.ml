open! Base
open Typed_sql_private
open Ast
open Expr.Infix

module Target = struct
  type row

  let table : row Table.t = Table.v_exn "merge_private_target"
  let id_column = Column.v_exn table "id" Db_type.int
  let value_column = Column.v_exn table "value" Db_type.int
  let id row = Expr.column row id_column
  let value row = Expr.column row value_column
end

module Source = struct
  type row

  let table : row Table.t = Table.v_exn "merge_private_source"
  let id_column = Column.v_exn table "id" Db_type.int
  let id row = Expr.column row id_column
end

let base_command () =
  Merge.(
    into Target.table
    |> using Source.table ~f:(fun target source merge ->
      merge
      |> on (Target.id target =. Source.id source)
      |> when_matched_update
           Assignments.(empty |> set_expr Target.value_column (Source.id source))))
  |> Merge.command
  |> Command.ast
;;

let normalized_error command = command |> Normalizer.command |> Validator.command

let%test "MERGE normalisation preserves forbidden command-field presence" =
  let command = base_command () in
  match normalized_error { command with where_ = Some True } with
  | Error (Invalid_merge _) -> true
  | Ok () | Error _ -> false
;;

let%test "MERGE rejects a malformed target source before lowering" =
  let command = base_command () in
  let command =
    { command with
      source =
        { command.source with
          kind = Values { descriptor_source_id = -1; columns = []; rows = [] }
        }
    }
  in
  match normalized_error command with
  | Error Invalid_command_target -> true
  | Ok () | Error _ -> false
;;

let%test "SQLite lowering rejects MERGE even when its only action does nothing" =
  let command =
    Merge.(
      into Target.table
      |> using Source.table ~f:(fun target source merge ->
        merge |> on (Target.id target =. Source.id source) |> when_matched_do_nothing))
    |> Merge.command
    |> Command.ast
  in
  match Lower.command ~dialect:Dialect.Sqlite command with
  | Error (Unsupported_operation { operation = "MERGE"; dialect = Dialect.Sqlite }) ->
    true
  | Ok _ | Error _ -> false
;;

let compile command = Compiler.compile_command_plan ~dialect:Dialect.Postgresql command

let compiled_merge value =
  let command =
    Merge.(
      into Target.table
      |> using Source.table ~f:(fun target source merge ->
        merge
        |> on (Target.id target =. Source.id source)
        |> when_matched_update Assignments.(empty |> set Target.value_column value)))
    |> Merge.command
  in
  compile (Command.ast command)
;;

let%test "MERGE shape excludes captured values and generative sources" =
  match compiled_merge 10, compiled_merge 20 with
  | Ok left, Ok right -> Shape.equal left.shape right.shape
  | Error _, _ | _, Error _ -> false
;;

let%test "MERGE shape records conditional branch structure" =
  let make condition =
    Merge.(
      into Target.table
      |> using Source.table ~f:(fun target source merge ->
        merge
        |> on (Target.id target =. Source.id source)
        |> when_matched_do_nothing ?condition))
    |> Merge.command
    |> Command.ast
    |> compile
  in
  match make None, make (Some Condition.true_) with
  | Ok left, Ok right -> not (Shape.equal left.shape right.shape)
  | Error _, _ | _, Error _ -> false
;;

let%test "MERGE rejects target and USING with the same source identity" =
  let command = base_command () in
  match command.kind with
  | Merge merge ->
    let command =
      { command with
        kind =
          Merge
            { merge with
              using = { merge.using with source_id = command.source.source_id }
            }
      }
    in
    (match normalized_error command with
     | Error (Invalid_merge "target and source must have distinct identities") -> true
     | Ok () | Error _ -> false)
  | Insert | Update | Delete -> false
;;

let%test "MERGE rejects a derived relation used as its target" =
  let command = base_command () in
  let relation =
    Derived_table.create
      ~table:Source.table
      ~columns:(fun row -> Projection.expr (Source.id row))
      Query.(from Source.table |> select (fun row -> Projection.expr (Source.id row)))
  in
  let command =
    { command with
      source = { command.source with kind = Derived (Derived_table.relation relation) }
    }
  in
  match normalized_error command with
  | Error Invalid_command_target -> true
  | Ok () | Error _ -> false
;;
