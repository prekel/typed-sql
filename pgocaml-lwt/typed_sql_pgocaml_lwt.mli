open! Base

(** Execute compiled typed SQL through PG'OCaml using Lwt. Parameters are sent
    separately from SQL, and result rows are decoded from the query projection. *)

(** The concrete PG'OCaml implementation used by this adapter. *)
module Pgocaml : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t

(** An error produced while binding, encoding, executing, or decoding a
    statement. *)
type constraint_kind =
  | Unique
  | Foreign_key
  | Not_null
  | Check
  | Restrict
  | Exclusion
  | Other (** A portable classification derived from PostgreSQL SQLSTATE. *)

type error =
  | Compile of Typed_sql.Statement.definition_error
  (** A dynamic statement failed compilation before database access. *)
  | Parameter of Typed_sql.Statement.binding_error
  (** A runtime statement parameter failed validation. *)
  | Encode of string
  (** A mapped parameter could not be converted to its database
        representation. *)
  | Decode of string
  (** A result field could not be converted to its OCaml representation. *)
  | Cardinality of
      { expected : string
        (** A human-readable expected cardinality, such as [exactly one]. *)
      ; actual : int (** The number of rows returned by PostgreSQL. *)
      } (** A single-row operation received an unexpected number of rows. *)
  | Constraint_violation of
      { kind : constraint_kind
      ; message : string
      } (** PostgreSQL reported an integrity-constraint SQLSTATE. *)
  | Invalid_cache_capacity of int
  (** [Prepared_cache.create] requires a positive capacity. *)
  | Prepared_cache_closed (** A closed prepared cache cannot execute more statements. *)
  | Pgocaml of exn
  (** PG'OCaml raised an exception while communicating with PostgreSQL. *)

(** Return a human-readable error description. *)
val error_to_string : error -> string

(** Format an error using [error_to_string]. *)
val pp_error : Formatter.t -> error -> unit

(** Resolve one input and execute a statement. Dynamic statements are built
    and compiled before database access. *)
val run
  :  conn:'connection Pgocaml.t
  -> ('input, 'output, [< `Postgresql ]) Typed_sql.Statement.t
  -> 'input
  -> ('output, error) Result.t Lwt.t

(** An opt-in cache of named PostgreSQL prepared statements. It belongs to one
    PG'OCaml connection and is bounded by [capacity]. Create a new cache for a
    new connection; call [close] before closing the connection. Closing is
    idempotent and releases cached statements on the server. *)
module Prepared_cache : sig
  type 'connection t

  val create
    :  ?capacity:int
    -> conn:'connection Pgocaml.t
    -> unit
    -> ('connection t, error) Result.t

  (** Execute a statement using a prepared handle keyed by its SQL and ordered
      PostgreSQL parameter types. An LRU entry is closed before replacement.
      Reusing a cache after schema changes may require closing it and creating
      a new one. *)
  val run
    :  'connection t
    -> ('input, 'output, [< `Postgresql ]) Typed_sql.Statement.t
    -> 'input
    -> ('output, error) Result.t Lwt.t

  (** Release prepared handles without closing the underlying connection. *)
  val close : 'connection t -> (unit, error) Result.t Lwt.t
end

(** Run [f] in a PostgreSQL transaction. [Ok] commits and [Error] rolls back.
    Raised PostgreSQL errors are classified after rollback. *)
val transaction
  :  conn:'connection Pgocaml.t
  -> f:('connection Pgocaml.t -> ('a, error) Result.t Lwt.t)
  -> ('a, error) Result.t Lwt.t
