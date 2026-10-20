open! Base

(** Dump-tool inputs. Exclusions use exact validated [(schema, table)]
    names; the URI may be supplied by the caller's environment instead. *)
type options =
  { uri : string option
    (** Explicit database URI, or [None] when not supplied on the command line. *)
  ; excluded_tables : (Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
    (** Exact validated schema/table pairs to omit from the dump. *)
  }

(** A requested help message or invalid command-line usage. Neither is
    a database introspection failure. *)
type argument_error =
  | Help (** The caller requested usage help. *)
  | Usage (** The argument list is malformed or contains unsupported options. *)

(** Shared CLI argument and table-exclusion behavior for both PostgreSQL
    dumpers. *)
val parse_args : string list -> (options, argument_error) Result.t

(** Remove exactly matching schema-qualified tables. Reject exclusions
    that match no table, so misspelled names cannot silently change a snapshot. *)
val exclude_tables
  :  (Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
  -> Typed_sql_schema.Schema_ir.t
  -> (Typed_sql_schema.Schema_ir.t, string) Result.t
