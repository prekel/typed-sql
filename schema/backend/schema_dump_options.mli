open! Base

(** Dump-tool inputs. Table filters use exact validated [(schema, table)]
    names; the URI may be supplied by the caller's environment instead. *)
type options =
  { uri : string option
    (** Explicit database URI, or [None] when not supplied on the command line. *)
  ; included_tables : (Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
    (** Exact validated schema/table pairs to retain; an empty list selects all tables. *)
  ; excluded_tables : (Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
    (** Exact validated schema/table pairs to omit from the dump. *)
  }

(** A requested help message or invalid command-line usage. Neither is
    a database introspection failure. *)
type argument_error =
  | Help (** The caller requested usage help. *)
  | Usage (** The argument list is malformed or contains unsupported options. *)

(** Parse an exact schema/table pair, including SQL-quoted identifiers. *)
val parse_qualified_table
  :  string
  -> (Typed_sql.Identifier.t * Typed_sql.Identifier.t, string) Result.t

(** Shared CLI argument behavior for both PostgreSQL dumpers. *)
val parse_args : string list -> (options, argument_error) Result.t

(** Retain the included tables (or all tables when the inclusion list is empty),
    then omit excluded tables. Both lists are validated against the original
    schema; any unknown name is an error. Repeated names are idempotent.
    Table order and retained tables' metadata, including foreign keys referencing
    omitted tables, are preserved. Referenced tables are not added implicitly. *)
val filter_tables
  :  included_tables:(Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
  -> excluded_tables:(Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
  -> Typed_sql_schema.Schema_ir.t
  -> (Typed_sql_schema.Schema_ir.t, string) Result.t
