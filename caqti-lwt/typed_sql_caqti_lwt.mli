open! Base

(** Execute compiled typed SQL through a Caqti Lwt connection. The adapter
    selects the SQL dialect from the connection and preserves bound parameters
    and projection decoding from [Typed_sql]. PostgreSQL date and timestamp
    text decoding requires ISO [DateStyle], including array elements and
    [Typed_sql.Local_timestamp] codecs. The adapter does not change [DateStyle]. *)

(** An error produced before or during execution. *)
type constraint_kind = Typed_sql.Constraint_error.kind =
  | Unique
  | Foreign_key
  | Not_null
  | Check
  | Restrict
  | Exclusion
  | Other
  (** A portable classification of integrity errors. Drivers may return [Other]
    when the database does not expose a more specific cause. *)

type error =
  | Compile of Typed_sql.Statement.definition_error
  (** A dynamic statement failed compilation before database access. *)
  | Unsupported_dialect of string
  (** The connected Caqti driver has no matching typed-sql dialect. *)
  | Dialect_mismatch of
      { expected : Typed_sql.Dialect.t
      ; connection : Typed_sql.Dialect.t
      } (** A statement requires a different connection dialect. *)
  | Parameter of Typed_sql.Statement.binding_error
  (** A runtime statement parameter failed validation before database access. *)
  | Codec of string
  (** A mapped [Typed_sql.Db_type] rejected parameter encoding or row decoding. *)
  | Constraint_violation of
      { kind : constraint_kind
      ; message : string
      ; cause : Caqti.Error.t
      }
  (** The database rejected a declared integrity constraint. [message] retains
      the backend diagnostic for logging and [cause] preserves the original
      driver error. *)
  | Rollback_failed of
      { error : error
      ; rollback_error : error
      }
  (** Rollback failed after an earlier failure. Both errors are retained;
      handle this as a transaction failure, not as a recoverable constraint. *)
  | Caqti of Caqti.Error.t
  (** Caqti or its driver rejected the request or database operation. *)

(** Return a human-readable error description. *)
val error_to_string : error -> string

(** Format an error using [error_to_string]. *)
val pp_error : Formatter.t -> error -> unit

(** Helpers for mapping adapter failures to application errors. *)
module Error : sig
  type t = error

  (** Return the portable classification and available diagnostic fields.
      Caqti exposes categories through its generic API; database object names
      and SQLSTATE are left absent. Use [cause] for driver-specific diagnostics.
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
  val cause : t -> Caqti.Error.t option

  val to_string : t -> string
  val pp : Formatter.t -> t -> unit
end

(** Measurements emitted for typed statement executions. Times are wall-clock
    seconds spent inside this adapter, including dynamic DSL construction and
    compilation during statement resolution. DSL construction before [run] is
    excluded. Events never contain SQL parameter values; each observed call
    emits one event, including resolution failures. *)
module Profile : sig
  type operation =
    | Resolve (** Failed before the execution operation could be resolved. *)
    | Fetch
    | Fetch_one
    | Fetch_opt
    | Execute

  type failure =
    | Compile (** Dynamic statement compilation failed during resolution. *)
    | Parameter (** Runtime input binding failed during resolution. *)
    | Encode
    | Database
    | Decode
    | Dialect
    | Cancelled
    | Raised

  type outcome =
    | Succeeded
    | Failed of failure

  type durations =
    { prepare : float option
      (** Statement resolution, binding, parameter encoding and request preparation,
          including dynamic callbacks and compilation. *)
    ; database : float option
    ; decode : float option
    ; total : float
    }

  type event =
    { name : string option
    ; operation : operation
    ; dialect : Typed_sql.Dialect.t option
    ; fingerprint : string option
    ; parameter_count : int option
    ; row_count : int option
    ; outcome : outcome
    ; durations : durations
    }

  type observer = event -> unit
end

(** A bounded in-memory aggregation of {!Profile.event} values. This module is
    intended for local diagnosis; production metrics systems can consume the
    same events directly. *)
module Profiler : sig
  type t

  type entry =
    { name : string option
    ; operation : Profile.operation
    ; fingerprint : string option
    ; parameter_count : int option
    ; calls : int
    ; failures : int
    ; rows : int
    ; prepare_seconds : float
    ; database_seconds : float
    ; decode_seconds : float
    ; total_seconds : float
    ; max_prepare_seconds : float
    ; max_database_seconds : float
    ; max_decode_seconds : float
    ; max_total_seconds : float
    }

  type snapshot =
    { entries : entry list
    ; overflow_calls : int
    ; overflow_seconds : float
    }

  (** Create an aggregator retaining at most [max_shapes] distinct
      [(name, operation, fingerprint)] groups. Additional groups
      contribute to the overflow counters. *)
  val create : ?max_shapes:int -> unit -> t

  (** Record one event. *)
  val record : t -> Profile.event -> unit

  (** Return a callback suitable for the execution functions below. *)
  val observer : t -> Profile.observer

  (** Return up to [limit] groups, ordered by cumulative adapter-preparation
      time. *)
  val snapshot : ?limit:int -> t -> snapshot

  (** Return [snapshot] and clear all accumulated data. *)
  val snapshot_and_reset : ?limit:int -> t -> snapshot

  (** Clear all accumulated data. *)
  val reset : t -> unit

  (** Print a compact report. Preparation time is an upper bound for potential
      future server-prepared-query savings. *)
  val pp : Formatter.t -> snapshot -> unit
end

(** Resolve [input] and execute the statement with its selected cardinality.
    Static statements bind an existing plan; dynamic statements build and
    compile one plan before adapter profiling and database access. *)
val run
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> ('input, 'output, 'requirements) Typed_sql.Statement.t
  -> 'input
  -> ('output, error) Result.t Lwt.t

(** Run [f] inside one transaction on [conn]. [Ok] commits and [Error] rolls
    back. A failed commit is also followed by rollback before its error is
    returned. [Rollback_failed] retains both failures when rollback also fails.
    An exception rolls back and is re-raised after cleanup, including
    [Lwt.Canceled], even if cleanup fails. *)
val transaction
  :  conn:Caqti_lwt.connection
  -> f:(Caqti_lwt.connection -> ('a, error) Result.t Lwt.t)
  -> ('a, error) Result.t Lwt.t
