open! Base

val result_query : Ast.result_query -> (unit, Compile_error.t) Result.t
val command : Ast.command -> (unit, Compile_error.t) Result.t
