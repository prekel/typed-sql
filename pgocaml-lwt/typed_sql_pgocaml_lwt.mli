open! Base

(** Execute compiled typed SQL through PG'OCaml using Lwt. Parameters are sent
    separately from SQL, and result rows are decoded from the query projection. *)

(** The concrete PG'OCaml implementation used by this adapter. *)
module Pgocaml : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t

(** An error produced while compiling, encoding, executing, or decoding a
    query. *)
type error =
  | Compile of Typed_sql.Compile_error.t
  (** The typed query failed validation or compilation. *)
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
  | Pgocaml of exn
  (** PG'OCaml raised an exception while communicating with PostgreSQL. *)

(** Return a human-readable error description. *)
val error_to_string : error -> string

(** Format an error using [error_to_string]. *)
val pp_error : Formatter.t -> error -> unit

(** Execute a query and collect every row in the order returned by PostgreSQL.
    Use [Typed_sql.Query.order_by] when the order is significant. *)
val fetch
  :  conn:'connection Pgocaml.t
  -> 'result Typed_sql.Result_query.t
  -> ('result list, error) Result.t Lwt.t

(** Execute a query which must return exactly one row. No [LIMIT] is added;
    zero or multiple rows return [Cardinality]. *)
val fetch_one
  :  conn:'connection Pgocaml.t
  -> 'result Typed_sql.Result_query.t
  -> ('result, error) Result.t Lwt.t

(** Execute a query which may return zero or one row. No [LIMIT] is added;
    multiple rows return [Cardinality]. *)
val fetch_opt
  :  conn:'connection Pgocaml.t
  -> 'result Typed_sql.Result_query.t
  -> ('result option, error) Result.t Lwt.t

(** Execute a command. PG'OCaml does not expose a portable affected-row count,
    so a successful result is [Typed_sql.Affected_rows.Unknown]. Unexpected
    result rows return [Cardinality]. *)
val execute
  :  conn:'connection Pgocaml.t
  -> Typed_sql.Command.t
  -> (Typed_sql.Affected_rows.t, error) Result.t Lwt.t
