open! Base

type result_query
type command

val result_query
  :  dialect:Dialect.t
  -> Ast.result_query
  -> (result_query, Compile_error.t) Result.t

val command : dialect:Dialect.t -> Ast.command -> (command, Compile_error.t) Result.t

module Private : sig
  val result_query_ast : result_query -> Ast.result_query
  val command_ast : command -> Ast.command
end
