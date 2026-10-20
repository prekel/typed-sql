open! Base

(** Introspect PostgreSQL with an existing Lwt PG'OCaml module. The functor
    preserves that module's connection type. *)
module Make (P : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t) : sig
  (** Invalid schema metadata or a driver exception encountered while reading catalogs. *)
  type error =
    | Schema of string
    (** Catalog metadata could not be converted to a valid schema snapshot. *)
    | Pgocaml_error of exn
    (** The PG'OCaml driver raised while reading schema metadata. *)

  (** Return a human-readable introspection error. *)
  val error_to_string : error -> string

  (** Read application tables and constraints. Ordinary unique column indexes
      are included; partial and expression indexes are omitted, and INCLUDE
      columns are not unique keys. Unknown types remain unsupported. *)
  val introspect
    :  conn:'connection P.t
    -> (Typed_sql_schema.Schema_ir.t, error) Result.t Lwt.t
end

(** Standard PG'OCaml introspector, sharing the execution adapter's default
    connection type. *)
type error =
  | Schema of string
  (** Catalog metadata could not be converted to a valid schema snapshot. *)
  | Pgocaml_error of exn (** The PG'OCaml driver raised while reading schema metadata. *)

(** Return a human-readable introspection error. *)
val error_to_string : error -> string

(** Read application tables and constraints with the same index and SQL-type
    handling as [Make.introspect]. *)
val introspect
  :  conn:'connection Typed_sql_pgocaml_lwt.Pgocaml.t
  -> (Typed_sql_schema.Schema_ir.t, error) Result.t Lwt.t
