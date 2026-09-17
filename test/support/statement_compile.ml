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

  let compile ~dialect query =
    Statement.For_dialect.query_many ~dialect (fun _ -> query)
    |> Result.map_error ~f:query_error
    |> Result.map ~f:(fun statement ->
      ({ dialect = Dialect.kind dialect
       ; sql = Statement.sql_exn ~dialect:(Dialect.kind dialect) ~input:() statement
       }
       : _ Compiled_query.t))
  ;;

  let compile_portable ~dialect query =
    Statement.Portable.query_many (fun _ -> query)
    |> Result.map_error ~f:query_error
    |> Result.map ~f:(fun statement ->
      let sql = Statement.sql_exn ~dialect ~input:() statement in
      ({ dialect; sql } : _ Compiled_query.t))
  ;;

  let compile_command ~dialect command =
    Statement.For_dialect.command ~dialect (fun _ -> command)
    |> Result.map_error ~f:command_error
    |> Result.map ~f:(fun statement ->
      ({ dialect = Dialect.kind dialect
       ; sql = Statement.sql_exn ~dialect:(Dialect.kind dialect) ~input:() statement
       }
       : Compiled_command.t))
  ;;

  let compile_portable_command ~dialect command =
    Statement.Portable.command (fun _ -> command)
    |> Result.map_error ~f:command_error
    |> Result.map ~f:(fun statement ->
      let sql = Statement.sql_exn ~dialect ~input:() statement in
      ({ dialect; sql } : Compiled_command.t))
  ;;
end
