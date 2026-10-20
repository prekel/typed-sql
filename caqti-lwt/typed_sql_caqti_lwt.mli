open! Base

(** Execute compiled typed SQL through a Caqti Lwt connection. The adapter
    selects the SQL dialect from the connection and preserves bound parameters
    and projection decoding from [Typed_sql]. PostgreSQL date and timestamp
    text decoding requires ISO [DateStyle], including array elements and
    [Typed_sql.Local_timestamp] codecs. The adapter does not change [DateStyle]. *)

(** Portable integrity categories shared with the core DSL. *)
type constraint_kind = Typed_sql.Constraint_error.kind =
  | Unique (** A unique key or primary key was violated. *)
  | Foreign_key (** A foreign-key constraint was violated. *)
  | Not_null (** SQL NULL was rejected by a non-null constraint. *)
  | Check (** A CHECK constraint rejected the row. *)
  | Restrict (** A referenced row is protected by a restriction. *)
  | Exclusion (** A PostgreSQL exclusion constraint was violated. *)
  | Other
  (** A portable classification of integrity errors. Drivers may return [Other]
    when the database does not expose a more specific cause. *)

(** Failures during statement resolution, binding, execution or decoding. *)
type error =
  | Compile of Typed_sql.Statement.definition_error
  (** A dynamic statement failed compilation before database access. *)
  | Unsupported_dialect of string
  (** The connected Caqti driver has no matching typed-sql dialect. *)
  | Dialect_mismatch of
      { expected : Typed_sql.Dialect.t (** Dialect required by the statement. *)
      ; connection : Typed_sql.Dialect.t (** Dialect reported by the connected driver. *)
      } (** A statement requires a different connection dialect. *)
  | Parameter of Typed_sql.Statement.binding_error
  (** A runtime statement parameter failed validation before database access. *)
  | Codec of string
  (** A mapped [Typed_sql.Db_type] rejected parameter encoding or row decoding. *)
  | Constraint_violation of
      { kind : constraint_kind
        (** Portable classification derived from backend diagnostics. *)
      ; message : string (** Backend diagnostic; may contain database values. *)
      ; cause : Caqti.Error.t
        (** Original driver failure with available backend details. *)
      }
  (** The database rejected a declared integrity constraint. [message] retains
      the backend diagnostic for logging and [cause] preserves the original
      driver error. *)
  | Rollback_failed of
      { error : error (** The operation or commit failure that triggered rollback. *)
      ; rollback_error : error
        (** The additional failure encountered while rolling back. *)
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
  (** Alias of the adapter error type for error-handling helpers. *)
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

  (** Return the same diagnostic as [error_to_string]. *)
  val to_string : t -> string

  (** Format the same diagnostic as [pp_error]. *)
  val pp : Formatter.t -> t -> unit
end

(** Measurements emitted for typed statement executions. Times are wall-clock
    seconds spent inside this adapter, including dynamic DSL construction and
    compilation during statement resolution. DSL construction before [run] is
    excluded. Events never contain SQL parameter values; each observed call
    emits one event, including resolution failures. *)
module Profile : sig
  (** The resolved row cardinality or command operation. [Resolve] marks
      a failure before an executable operation was selected. *)
  type operation =
    | Resolve (** Failed before the execution operation could be resolved. *)
    | Fetch (** Execute a query returning any number of rows. *)
    | Fetch_one (** Execute a query requiring exactly one row. *)
    | Fetch_opt (** Execute a query requiring zero or one row. *)
    | Execute (** Execute a command returning an affected-row result. *)

  (** The adapter phase or exceptional outcome responsible for a failure. *)
  type failure =
    | Compile (** Dynamic statement compilation failed during resolution. *)
    | Parameter (** Runtime input binding failed during resolution. *)
    | Encode (** Parameter encoding failed. *)
    | Database (** The database or driver rejected execution. *)
    | Decode (** Result decoding failed. *)
    | Dialect (** The connection dialect was unsupported or mismatched. *)
    | Cancelled (** The observed call was cancelled through Lwt. *)
    | Raised (** The observed call raised an exception outside ordinary error results. *)

  (** Success or a classified failure for one observed execution. *)
  type outcome =
    | Succeeded (** The adapter returned an [Ok] result. *)
    | Failed of failure
    (** The adapter failed in the indicated phase or exceptional outcome. *)

  (** Wall-clock seconds per measured phase. [None] means the phase was
      not measured; [total] spans the observed adapter call. *)
  type durations =
    { prepare : float option
      (** Statement resolution, binding, parameter encoding and request preparation,
          including dynamic callbacks and compilation. *)
    ; database : float option
      (** Measured driver/database phase in seconds, when reached. *)
    ; decode : float option
      (** Measured result-decoding phase in seconds, when available. *)
    ; total : float (** Total wall-clock seconds for the observed adapter call. *)
    }

  (** One execution observation. Optional fields are absent when the
      corresponding plan or result was unavailable. Fingerprints identify
      statement shapes and never include bound parameter values. *)
  type event =
    { name : string option (** Optional application-supplied operation name. *)
    ; operation : operation
      (** Resolved execution operation, or [Resolve] on early failure. *)
    ; dialect : Typed_sql.Dialect.t option
      (** Connection dialect, when successfully identified. *)
    ; fingerprint : string option
      (** Statement-shape fingerprint, excluding parameter values. *)
    ; parameter_count : int option
      (** Number of resolved distinct bind slots, when available. *)
    ; row_count : int option (** Decoded row or affected-row count, when available. *)
    ; outcome : outcome (** Success or the classified failure. *)
    ; durations : durations (** Measured durations for this call. *)
    }

  (** Synchronous callback invoked once per observed call. Observers should
      return promptly and avoid raising exceptions. *)
  type observer = event -> unit
end

(** A bounded in-memory aggregation of {!Profile.event} values. This module is
    intended for local diagnosis; production metrics systems can consume the
    same events directly. *)
module Profiler : sig
  (** Mutable bounded aggregation state, independent of the database connection. *)
  type t

  (** Counters and accumulated/maximal wall-clock durations for one
      [(name, operation, fingerprint)] group. [rows] sums reported row counts. *)
  type entry =
    { name : string option (** Application name shared by this group. *)
    ; operation : Profile.operation (** Execution operation shared by this group. *)
    ; fingerprint : string option (** Resolved shape fingerprint shared by this group. *)
    ; parameter_count : int option
      (** First available parameter count reported for the group. *)
    ; calls : int (** Number of observed calls in the group. *)
    ; failures : int (** Number of calls with a failed outcome. *)
    ; rows : int (** Sum of available row counts; absent counts contribute zero. *)
    ; prepare_seconds : float
      (** Sum of measured preparation seconds; absent durations contribute zero. *)
    ; database_seconds : float
      (** Sum of measured database seconds; absent durations contribute zero. *)
    ; decode_seconds : float
      (** Sum of measured decoding seconds; absent durations contribute zero. *)
    ; total_seconds : float (** Sum of total wall-clock seconds. *)
    ; max_prepare_seconds : float
      (** Largest measured preparation duration, or zero if unavailable. *)
    ; max_database_seconds : float
      (** Largest measured database duration, or zero if unavailable. *)
    ; max_decode_seconds : float
      (** Largest measured decoding duration, or zero if unavailable. *)
    ; max_total_seconds : float (** Largest total call duration in seconds. *)
    }

  (** A detached report of retained groups and calls omitted by the shape
      capacity limit. Reading a snapshot does not reset the aggregator. *)
  type snapshot =
    { entries : entry list (** Retained groups, ordered by cumulative preparation time. *)
    ; overflow_calls : int (** Calls belonging to groups omitted by the capacity limit. *)
    ; overflow_seconds : float (** Total wall-clock seconds for omitted calls. *)
    }

  (** Create an aggregator retaining at most [max_shapes] distinct
      [(name, operation, fingerprint)] groups. Additional groups
      contribute to the overflow counters. [max_shapes] defaults to 1024;
      non-positive values raise [Invalid_argument]. *)
  val create : ?max_shapes:int -> unit -> t

  (** Record one event. *)
  val record : t -> Profile.event -> unit

  (** Return a callback suitable for the execution functions below. *)
  val observer : t -> Profile.observer

  (** Return up to [limit] groups, ordered by cumulative adapter-preparation
      time. [limit] defaults to 20; negative limits raise [Invalid_argument]. *)
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
    compile one plan during measured preparation, before database access. *)
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
