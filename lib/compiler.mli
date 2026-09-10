open! Base

val compile
  :  dialect:Dialect.t
  -> ('ctx, 'result) Query.t
  -> ('result Compiled_query.t, Compile_error.t) Result.t
