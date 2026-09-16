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
  | Compile of Typed_sql.Compile_error.t
  (** The typed query failed validation or compilation. *)
  | Unsupported_dialect of string
  (** The connected Caqti driver has no matching typed-sql dialect. *)
  | Dialect_mismatch of
      { compiled : Typed_sql.Dialect.t
      ; connection : Typed_sql.Dialect.t
      } (** A compiled statement was rendered for a different connection dialect. *)
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
    | Compile
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
    { compile : float option
    ; prepare : float option
    ; database : float option
    ; decode : float option
    ; total : float
    }

  type event =
    { name : string option
    ; operation : operation
    ; compiled : bool
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
    ; compiled : bool
    ; fingerprint : string option
    ; parameter_count : int option
    ; calls : int
    ; failures : int
    ; rows : int
    ; compile_seconds : float
    ; prepare_seconds : float
    ; database_seconds : float
    ; decode_seconds : float
    ; total_seconds : float
    ; max_compile_seconds : float
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
      [(name, operation, compiled mode, fingerprint)] groups. Additional groups
      contribute to the overflow counters. *)
  val create : ?max_shapes:int -> unit -> t

  (** Record one event. *)
  val record : t -> Profile.event -> unit

  (** Return a callback suitable for the execution functions below. *)
  val observer : t -> Profile.observer

  (** Return up to [limit] groups, ordered by cumulative compilation and
      adapter-preparation time. *)
  val snapshot : ?limit:int -> t -> snapshot

  (** Return [snapshot] and clear all accumulated data. *)
  val snapshot_and_reset : ?limit:int -> t -> snapshot

  (** Clear all accumulated data. *)
  val reset : t -> unit

  (** Print a compact report. Potential compiled savings are represented by
      compilation time; preparation time is an upper bound for additional
      future prepared-query savings. *)
  val pp : Formatter.t -> snapshot -> unit
end

(** Execute a query and collect every row in the order returned by the
    database. Use [Typed_sql.Query.order_by] when the order is significant. *)
val fetch
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result list, error) Result.t Lwt.t

(** Execute an already compiled query. Compilation time is absent from the
    emitted profile event. *)
val fetch_compiled
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> 'result Typed_sql.Compiled_query.t
  -> ('result list, error) Result.t Lwt.t

(** Execute a query which must return exactly one row. The adapter adds no
    [LIMIT]; zero or multiple rows produce a Caqti cardinality error. *)
val fetch_one
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result, error) Result.t Lwt.t

val fetch_one_compiled
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> 'result Typed_sql.Compiled_query.t
  -> ('result, error) Result.t Lwt.t

(** Execute a query which may return zero or one row. The adapter adds no
    [LIMIT]; multiple rows produce a Caqti cardinality error. *)
val fetch_opt
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result option, error) Result.t Lwt.t

val fetch_opt_compiled
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> 'result Typed_sql.Compiled_query.t
  -> ('result option, error) Result.t Lwt.t

(** Execute a command. The result is [Affected_rows.Unknown] when the Caqti
    driver cannot report an affected-row count. *)
val execute
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> Typed_sql.Command.t
  -> (Typed_sql.Affected_rows.t, error) Result.t Lwt.t

val execute_compiled
  :  ?observer:Profile.observer
  -> ?name:string
  -> conn:Caqti_lwt.connection
  -> Typed_sql.Compiled_command.t
  -> (Typed_sql.Affected_rows.t, error) Result.t Lwt.t

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
