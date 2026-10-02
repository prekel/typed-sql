open! Base

(** Introspect PostgreSQL with an existing Lwt PG'OCaml module. The functor
    preserves that module's connection type. *)
module Make (P : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t) : sig
  type error =
    | Schema of string
    | Pgocaml_error of exn

  val error_to_string : error -> string

  val introspect
    :  conn:'connection P.t
    -> (Typed_sql_schema.Schema_ir.t, error) Result.t Lwt.t
end

(** Standard PG'OCaml introspector, sharing the execution adapter's default
    connection type. *)
type error =
  | Schema of string
  | Pgocaml_error of exn

val error_to_string : error -> string

val introspect
  :  conn:'connection Typed_sql_pgocaml_lwt.Pgocaml.t
  -> (Typed_sql_schema.Schema_ir.t, error) Result.t Lwt.t
