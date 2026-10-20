open! Base

(** Adapter-neutral outcomes expected by the shared MERGE scenarios. *)
type error =
  | Check_violation
  (** Expected integrity failure from a MERGE fixture CHECK constraint. *)
  | Database_error of string
  (** A backend execution failure retained for test diagnostics. *)
  | Unexpected_error of string
  (** An adapter failure outside the expected constraint/database categories. *)

(** Operations on one test-owned connection. [exec_sql] installs trusted
    fixtures; [run] executes typed PostgreSQL statements through an adapter. *)
type runner =
  { exec_sql : string -> unit Lwt.t
    (** Execute trusted fixture SQL on the runner's connection. *)
  ; run :
      'output.
      (unit, 'output, [ `Postgresql ]) Typed_sql.Statement.t
      -> ('output, error) Result.t Lwt.t
    (** Execute a parameterless typed statement on the same connection as the fixtures. *)
  }

(** Run the same public-API MERGE scenarios through either PostgreSQL adapter.
    The runner owns one connection; fixtures are temporary tables. *)
val run : runner -> unit Lwt.t
