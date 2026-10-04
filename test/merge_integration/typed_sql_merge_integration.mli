open! Base

type error =
  | Check_violation
  | Database_error of string
  | Unexpected_error of string

type runner =
  { exec_sql : string -> unit Lwt.t
  ; run :
      'output.
      (unit, 'output, [ `Postgresql ]) Typed_sql.Statement.t
      -> ('output, error) Result.t Lwt.t
  }

(** Run the same public-API MERGE scenarios through either PostgreSQL adapter.
    The runner owns one connection; fixtures are temporary tables. *)
val run : runner -> unit Lwt.t
