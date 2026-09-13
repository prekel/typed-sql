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

(** Execute a query and collect every row in the order returned by the
    database. Use [Typed_sql.Query.order_by] when the order is significant. *)
val fetch
  :  conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result list, error) Result.t Lwt.t

(** Execute a query which must return exactly one row. The adapter adds no
    [LIMIT]; zero or multiple rows produce a Caqti cardinality error. *)
val fetch_one
  :  conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result, error) Result.t Lwt.t

(** Execute a query which may return zero or one row. The adapter adds no
    [LIMIT]; multiple rows produce a Caqti cardinality error. *)
val fetch_opt
  :  conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result option, error) Result.t Lwt.t

(** Execute a command. The result is [Affected_rows.Unknown] when the Caqti
    driver cannot report an affected-row count. *)
val execute
  :  conn:Caqti_lwt.connection
  -> Typed_sql.Command.t
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
