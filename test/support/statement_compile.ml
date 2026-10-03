open! Base
open Typed_sql

module Compiled_query = struct
  type 'result t =
    { dialect : Dialect.t
    ; sql : string
    }

  let dialect t = t.dialect
  let sql t = t.sql
  let pp formatter t = Stdlib.Format.pp_print_string formatter t.sql
end

module Compiled_command = struct
  type t =
    { dialect : Dialect.t
    ; sql : string
    }

  let dialect t = t.dialect
  let sql t = t.sql
  let pp formatter t = Stdlib.Format.pp_print_string formatter t.sql
end

module Compiler = struct
  let query_error (error : Statement.definition_error) = error.error
  let command_error = query_error

  let compile_result build =
    try Ok (build ()) with
    | Statement.Definition_error error -> Error error
  ;;

  let render_statement
    : type requirements supports output.
      (requirements, supports) Dialect.supports
      -> (unit, output, supports) Statement.t
      -> Dialect.t * string
    =
    fun dialect statement ->
    match dialect with
    | Dialect.Portable ->
      Dialect.Postgresql, Statement.sql_exn ~dialect:postgresql ~input:() statement
    | Dialect.Concrete_postgresql ->
      Dialect.Postgresql, Statement.sql_exn ~dialect:postgresql ~input:() statement
    | Dialect.Concrete_sqlite ->
      Dialect.Sqlite, Statement.sql_exn ~dialect:sqlite ~input:() statement
  ;;

  let compile ~dialect query =
    compile_result (fun () -> Statement.query_many ~dialect query)
    |> Result.map_error ~f:query_error
    |> Result.map ~f:(fun statement ->
      let dialect, sql = render_statement dialect statement in
      ({ dialect; sql } : _ Compiled_query.t))
  ;;

  let compile_portable ~dialect query =
    compile_result (fun () -> Statement.query_many ~dialect:Dialect.portable query)
    |> Result.map_error ~f:query_error
    |> Result.map ~f:(fun statement ->
      let sql =
        match dialect with
        | Dialect.Postgresql -> Statement.sql_exn ~dialect:postgresql ~input:() statement
        | Dialect.Sqlite -> Statement.sql_exn ~dialect:sqlite ~input:() statement
      in
      ({ dialect; sql } : _ Compiled_query.t))
  ;;

  let compile_command ~dialect command =
    compile_result (fun () -> Statement.command ~dialect command)
    |> Result.map_error ~f:command_error
    |> Result.map ~f:(fun statement ->
      let dialect, sql = render_statement dialect statement in
      ({ dialect; sql } : Compiled_command.t))
  ;;

  let compile_portable_command ~dialect command =
    compile_result (fun () -> Statement.command ~dialect:Dialect.portable command)
    |> Result.map_error ~f:command_error
    |> Result.map ~f:(fun statement ->
      let sql =
        match dialect with
        | Dialect.Postgresql -> Statement.sql_exn ~dialect:postgresql ~input:() statement
        | Dialect.Sqlite -> Statement.sql_exn ~dialect:sqlite ~input:() statement
      in
      ({ dialect; sql } : Compiled_command.t))
  ;;
end
