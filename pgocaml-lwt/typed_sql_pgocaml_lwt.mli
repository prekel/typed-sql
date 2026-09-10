open! Base
module Pgocaml : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t

type error =
  | Compile of Typed_sql.Compile_error.t
  | Encode of string
  | Decode of string
  | Cardinality of
      { expected : string
      ; actual : int
      }
  | Pgocaml of exn

val error_to_string : error -> string
val pp_error : Formatter.t -> error -> unit

val fetch
  :  conn:'connection Pgocaml.t
  -> 'result Typed_sql.Result_query.t
  -> ('result list, error) Result.t Lwt.t

val fetch_one
  :  conn:'connection Pgocaml.t
  -> 'result Typed_sql.Result_query.t
  -> ('result, error) Result.t Lwt.t

val fetch_opt
  :  conn:'connection Pgocaml.t
  -> 'result Typed_sql.Result_query.t
  -> ('result option, error) Result.t Lwt.t

val execute
  :  conn:'connection Pgocaml.t
  -> Typed_sql.Command.t
  -> (Typed_sql.Affected_rows.t, error) Result.t Lwt.t
