open! Base

(** Logical PostgreSQL type metadata shared with schema snapshots. *)
module Type_info = Typed_sql_schema.Schema_ir

(** One described result column, in server-reported output order. *)
type field =
  { name : string (** Result-column name in the SQL output layout. *)
  ; typ : Type_info.postgresql_type_info
    (** Exact logical PostgreSQL type, with no database-specific OID. *)
  ; nullable : bool (** Whether decoding wraps the field value in an option. *)
  }

(** Exact rewritten SQL and ordered Prepare/Describe metadata. [None]
    means a command result; [Some] contains a nonempty result layout. *)
type entry =
  { sql : string
    (** Exact SQL after rewriting OCaml substitutions to positional placeholders. *)
  ; parameters : Type_info.postgresql_type_info list
    (** Parameter types in positional-placeholder order. *)
  ; result : field list option
    (** Absent for a command; otherwise a nonempty ordered output layout. *)
  }

(** Validated offline metadata for one role and search-path configuration. *)
type t

(** One cache describes one PostgreSQL role and configured search path.
    Entries contain logical types, never database-specific OIDs. Duplicate SQL,
    unsupported codecs and zero-column row results are rejected. *)
val create : role:string -> search_path:string -> entry list -> (t, string) Result.t

(** Decode and validate cached JSON metadata, rejecting unsupported
    codecs and inconsistent entries as in [create]. *)
val of_string : string -> (t, string) Result.t

(** Serialize logical metadata for offline reuse; no database OIDs or
    runtime parameter values are persisted. *)
val to_string : t -> string

(** Emit a module registering validated, embedded metadata. No JSON file is
    opened by the resulting PPX driver. *)
val codegen : t -> string

(** Resolve the exact rewritten SQL and attach the current OCaml expressions.
    Missing metadata is an error; no database or schema-inference fallback runs. *)
val plan : t -> Query_bind.t -> (Statement_plan.t, Sql.error) Result.t
