open! Base

(** Execute compiled typed SQL through PG'OCaml using Lwt. Parameters are sent
    separately from SQL, and result rows are decoded from the query projection.
    Connections must use ISO [DateStyle] for date and timestamp results,
    including array elements. The adapter does not change session settings. *)

(** The concrete PG'OCaml implementation used by this adapter. *)
module Pgocaml : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t

(** Portable integrity categories derived from PostgreSQL SQLSTATE. *)
type constraint_kind = Typed_sql.Constraint_error.kind =
  | Unique (** A unique key or primary key was violated. *)
  | Foreign_key (** A foreign-key constraint was violated. *)
  | Not_null (** SQL NULL was rejected by a non-null constraint. *)
  | Check (** A CHECK constraint rejected the row. *)
  | Restrict (** A referenced row is protected by a restriction. *)
  | Exclusion (** A PostgreSQL exclusion constraint was violated. *)
  | Other (** A portable classification derived from PostgreSQL SQLSTATE. *)

(** Failures during statement resolution, binding, execution or decoding. *)
type error =
  | Compile of Typed_sql.Statement.definition_error
  (** A dynamic statement failed compilation before database access. *)
  | Unsupported_dialect of Typed_sql.Dialect.t
  (** The statement has no plan for the PostgreSQL adapter's dialect. *)
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
        (** Portable classification derived from backend diagnostics. *)
      ; message : string (** Backend diagnostic; may contain database values. *)
      ; cause : exn (** Original driver failure with available backend details. *)
      }
  (** PostgreSQL reported an integrity-constraint SQLSTATE; [cause] retains
            the original exception and all protocol diagnostic fields. *)
  | Invalid_cache_capacity of int
  (** [Prepared_cache.create] requires a positive capacity. *)
  | Prepared_cache_closed (** A closed prepared cache cannot execute more statements. *)
  | Rollback_failed of
      { error : error (** The operation or commit failure that triggered rollback. *)
      ; rollback_error : error
        (** The additional failure encountered while rolling back. *)
      }
  (** Rollback failed after an earlier failure. Both errors are retained;
      handle this as a transaction failure, not as a recoverable constraint. *)
  | Pgocaml of exn
  (** PG'OCaml raised an exception while communicating with PostgreSQL. *)

(** Return a human-readable error description. *)
val error_to_string : error -> string

(** Format an error using [error_to_string]. *)
val pp_error : Formatter.t -> error -> unit

(** Helpers for mapping adapter failures to application errors. *)
module Error : sig
  (** Alias of the adapter error type for error-handling helpers. *)
  type t = error

  (** Return the portable classification and available diagnostic fields.
      Non-constraint failures and [Rollback_failed] return [None]. *)
  val constraint_violation : t -> Typed_sql.Constraint_error.t option

  (** Match only constraint errors. Missing diagnostic names never satisfy a
      name filter. With no filters, any constraint violation matches. *)
  val is_constraint_violation
    :  ?kind:Typed_sql.Constraint_error.kind
    -> ?constraint_name:string
    -> ?schema_name:string
    -> ?table_name:string
    -> ?column_name:string
    -> t
    -> bool

  (** The original driver error, also retained for classified violations.
      For [Rollback_failed], return the first failure's driver cause; the
      rollback error remains available in the variant. *)
  val cause : t -> exn option

  (** Return the same diagnostic as [error_to_string]. *)
  val to_string : t -> string

  (** Format the same diagnostic as [pp_error]. *)
  val pp : Formatter.t -> t -> unit
end

(** Resolve one input and execute a statement. Dynamic statements are built
    and compiled before database access. *)
val run
  :  conn:'connection Pgocaml.t
  -> ('input, 'output, [> `Postgresql ]) Typed_sql.Statement.t
  -> 'input
  -> ('output, error) Result.t Lwt.t

(** An opt-in cache of named PostgreSQL prepared statements. It belongs to one
    PG'OCaml connection and is bounded by [capacity]. Create a new cache for a
    new connection; call [close] before closing the connection. Closing is
    idempotent and releases cached statements on the server. *)
module Prepared_cache : sig
  (** Mutable prepared handles owned by one connection. Do not share
      a cache across connections; close it before closing its connection. *)
  type 'connection t

  (** Create an empty cache without contacting PostgreSQL. [capacity]
      defaults to 32 and must be positive; otherwise return [Invalid_cache_capacity]. *)
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
    -> ('input, 'output, [> `Postgresql ]) Typed_sql.Statement.t
    -> 'input
    -> ('output, error) Result.t Lwt.t

  (** Release prepared handles without closing the underlying connection. *)
  val close : 'connection t -> (unit, error) Result.t Lwt.t
end

(** Run [f] in a PostgreSQL transaction. [Ok] commits and [Error] rolls back.
    Ordinary callback exceptions are classified as adapter errors before
    rollback. A failed commit is also followed by rollback; [Rollback_failed]
    retains both failures. [Lwt.Canceled] remains cancellation, even if the
    rollback attempt after cancellation fails. *)
val transaction
  :  conn:'connection Pgocaml.t
  -> f:('connection Pgocaml.t -> ('a, error) Result.t Lwt.t)
  -> ('a, error) Result.t Lwt.t

(** Build an adapter for an existing Lwt PG'OCaml module. The resulting
    connection type is the input module's type, so connections owned by an
    application pool can be passed to [run] directly. *)
module Make (P : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t) : sig
  (** The supplied driver with its connection type preserved. *)
  module Pgocaml :
    PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t and type 'a t = 'a P.t

  (** The same portable integrity categories as the default adapter. *)
  type constraint_kind = Typed_sql.Constraint_error.kind =
    | Unique (** A unique key or primary key was violated. *)
    | Foreign_key (** A foreign-key constraint was violated. *)
    | Not_null (** SQL NULL was rejected by a non-null constraint. *)
    | Check (** A CHECK constraint rejected the row. *)
    | Restrict (** A referenced row is protected by a restriction. *)
    | Exclusion (** A PostgreSQL exclusion constraint was violated. *)
    | Other (** An integrity failure without a more specific reported category. *)

  (** Execution failures with the same meanings as the default adapter,
      using exceptions from the supplied driver as causes. *)
  type error =
    | Compile of Typed_sql.Statement.definition_error
    (** A dynamic AST failed compilation before database access. *)
    | Unsupported_dialect of Typed_sql.Dialect.t
    (** The statement has no PostgreSQL execution plan. *)
    | Parameter of Typed_sql.Statement.binding_error
    (** Runtime input failed bind validation before database access. *)
    | Encode of string (** A parameter codec rejected its application value. *)
    | Decode of string (** A result codec rejected a returned database value. *)
    | Cardinality of
        { expected : string (** Required row cardinality, formatted for diagnostics. *)
        ; actual : int (** Number of rows returned by the database. *)
        } (** The returned row count does not satisfy the requested cardinality. *)
    | Constraint_violation of
        { kind : constraint_kind
          (** Portable classification derived from backend diagnostics. *)
        ; message : string (** Backend diagnostic; may contain database values. *)
        ; cause : exn (** Original driver failure with available backend details. *)
        } (** The database reported an integrity-constraint violation. *)
    | Invalid_cache_capacity of int
    (** Cache creation received a non-positive capacity. *)
    | Prepared_cache_closed (** Execution attempted to reuse a closed prepared cache. *)
    | Rollback_failed of
        { error : error (** The operation or commit failure that triggered rollback. *)
        ; rollback_error : error
          (** The additional failure encountered while rolling back. *)
        }
    (** Rollback failed after an earlier failure. Both errors are retained;
      handle this as a transaction failure, not as a recoverable constraint. *)
    | Pgocaml of exn
    (** The supplied driver raised an exception during a database operation. *)

  (** Return a human-readable error description. *)
  val error_to_string : error -> string

  (** Format an adapter error. *)
  val pp_error : Formatter.t -> error -> unit

  (** Helpers for mapping adapter failures to application errors. *)
  module Error : sig
    (** Alias of this functor instance's error type. *)
    type t = error

    (** Return the portable classification and available diagnostic fields.
        Non-constraint failures and [Rollback_failed] return [None]. *)
    val constraint_violation : t -> Typed_sql.Constraint_error.t option

    (** Match only constraint errors. Missing diagnostic names never satisfy a
        name filter. With no filters, any constraint violation matches. *)
    val is_constraint_violation
      :  ?kind:Typed_sql.Constraint_error.kind
      -> ?constraint_name:string
      -> ?schema_name:string
      -> ?table_name:string
      -> ?column_name:string
      -> t
      -> bool

    (** The original driver error, also retained for classified violations.
      For [Rollback_failed], return the first failure's driver cause; the
      rollback error remains available in the variant. *)
    val cause : t -> exn option

    (** Return the same diagnostic as this instance's [error_to_string]. *)
    val to_string : t -> string

    (** Format the same diagnostic as this instance's [pp_error]. *)
    val pp : Formatter.t -> t -> unit
  end

  (** Resolve and execute one input using the supplied driver.
      Dynamic construction and compilation precede database access. *)
  val run
    :  conn:'connection Pgocaml.t
    -> ('input, 'output, [> `Postgresql ]) Typed_sql.Statement.t
    -> 'input
    -> ('output, error) Result.t Lwt.t

  (** Connection-owned bounded prepared handles with the same lifetime
      and eviction rules as the default [Prepared_cache]. *)
  module Prepared_cache : sig
    (** Mutable prepared handles for one connection of the supplied driver. *)
    type 'connection t

    (** Create an empty cache. The capacity defaults to 32 and must be
        positive; invalid capacities return [Invalid_cache_capacity]. *)
    val create
      :  ?capacity:int
      -> conn:'connection Pgocaml.t
      -> unit
      -> ('connection t, error) Result.t

    (** Execute through the connection-owned LRU cache, keyed by SQL and
        ordered PostgreSQL parameter types. Closed caches reject execution. *)
    val run
      :  'connection t
      -> ('input, 'output, [> `Postgresql ]) Typed_sql.Statement.t
      -> 'input
      -> ('output, error) Result.t Lwt.t

    (** Release cached server statements, preserving the connection.
        Closing is idempotent. *)
    val close : 'connection t -> (unit, error) Result.t Lwt.t
  end

  (** Same transaction, exception, and cancellation contract as [transaction]
      above, using the supplied PG'OCaml module. *)
  val transaction
    :  conn:'connection Pgocaml.t
    -> f:('connection Pgocaml.t -> ('a, error) Result.t Lwt.t)
    -> ('a, error) Result.t Lwt.t
end
