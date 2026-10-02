open! Base

type options =
  { uri : string option
  ; excluded_tables : (Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
  }

type argument_error =
  | Help
  | Usage

(** Shared CLI argument and table-exclusion behavior for both PostgreSQL
    dumpers. *)
val parse_args : string list -> (options, argument_error) Result.t

val exclude_tables
  :  (Typed_sql.Identifier.t * Typed_sql.Identifier.t) list
  -> Typed_sql_schema.Schema_ir.t
  -> (Typed_sql_schema.Schema_ir.t, string) Result.t
