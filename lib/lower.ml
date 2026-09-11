open! Base

type result_query = Ast.result_query
type command = Ast.command

let has_default assignments =
  List.exists assignments ~f:(fun assignment ->
    match assignment.Ast.value with
    | Ast.Default -> true
    | Ast.Expression _ -> false)
;;

let unsupported operation dialect =
  Error (Compile_error.Unsupported_operation { operation; dialect })
;;

let command ~dialect command =
  match dialect, command.Ast.kind with
  | Dialect.Sqlite, Ast.Insert when List.exists command.rows ~f:has_default ->
    unsupported "INSERT DEFAULT" dialect
  | Dialect.Sqlite, Ast.Update when has_default command.assignments ->
    unsupported "UPDATE SET DEFAULT" dialect
  | Dialect.Sqlite, _ when Option.is_some command.conflict ->
    unsupported "Postgresql.Insert.on_conflict_do_nothing" dialect
  | _ -> Ok command
;;

let result_query ~dialect query =
  match query with
  | Ast.Select _ -> Ok query
  | Ast.Returning returning ->
    let open Result.Let_syntax in
    let%map command = command ~dialect returning.command in
    Ast.Returning { returning with command }
;;

let result_query_ast query = query
let command_ast command = command
