open! Base

val compile
  :  dialect:Dialect.t
  -> 'result Result_query.t
  -> ('result Compiled_query.t, Compile_error.t) Result.t

val compile_command
  :  dialect:Dialect.t
  -> Command.t
  -> (Compiled_command.t, Compile_error.t) Result.t
