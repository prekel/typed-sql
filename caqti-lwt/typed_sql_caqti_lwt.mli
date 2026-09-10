open! Base

type error =
  | Compile of Typed_sql.Compile_error.t
  | Unsupported_dialect of string
  | Caqti of Caqti.Error.t

val error_to_string : error -> string
val pp_error : Formatter.t -> error -> unit

(** Execute a query and collect every row in database order. *)
val fetch
  :  conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result list, error) Result.t Lwt.t

(** Execute a query which must return exactly one row. No [LIMIT] is added. *)
val fetch_one
  :  conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result, error) Result.t Lwt.t

(** Execute a query which may return zero or one row and fails on additional
    rows. No [LIMIT] is added. *)
val fetch_opt
  :  conn:Caqti_lwt.connection
  -> 'result Typed_sql.Result_query.t
  -> ('result option, error) Result.t Lwt.t

(** Execute a command and report the affected row count when the driver makes
    it available. *)
val execute
  :  conn:Caqti_lwt.connection
  -> Typed_sql.Command.t
  -> (Typed_sql.Affected_rows.t, error) Result.t Lwt.t
