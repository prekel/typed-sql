open! Base

(** Execute compiled typed SQL through a Caqti Lwt connection. The adapter
    selects the SQL dialect from the connection and preserves bound parameters
    and projection decoding from [Typed_sql]. *)

(** An error produced before or during execution. *)
type constraint_kind =
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
  | Schema of string
  (** Database metadata could not be converted to validated schema metadata. *)
  | Constraint_violation of
      { kind : constraint_kind
      ; message : string
      }
  (** The database rejected a declared integrity constraint. [message] retains
      the backend diagnostic for logging. *)
  | Caqti of Caqti.Error.t
  (** Caqti or its driver rejected the request or database operation. *)

(** Return a human-readable error description. *)
val error_to_string : error -> string

(** Format an error using [error_to_string]. *)
val pp_error : Formatter.t -> error -> unit

(** Measurements emitted for typed statement executions. Times are wall-clock
    seconds spent inside this adapter and exclude construction of the input DSL
    value. Events never contain SQL parameter values. *)
module Profile : sig
  type operation =
    | Fetch
    | Fetch_one
    | Fetch_opt
    | Execute

  type failure =
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
    returned. An exception rolls back and is re-raised after cleanup. *)
val transaction
  :  conn:Caqti_lwt.connection
  -> f:(Caqti_lwt.connection -> ('a, error) Result.t Lwt.t)
  -> ('a, error) Result.t Lwt.t

(** Database schema discovery for descriptor generation. *)
module Schema : sig
  (** Read ordinary application tables, columns, defaults, generated columns,
      primary keys, foreign keys and unique constraints. SQLite system tables
      and PostgreSQL system schemas are excluded. Unknown database types are
      preserved as [Typed_sql.Schema_ir.Unsupported] instead of being guessed. *)
  val introspect
    :  conn:Caqti_lwt.connection
    -> (Typed_sql.Schema_ir.t, error) Result.t Lwt.t
end
