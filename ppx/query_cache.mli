open! Base

(** Logical PostgreSQL type metadata shared with schema snapshots. *)
module Type_info = Typed_sql_schema.Schema_ir

(** Server-accepted statement category and placement restrictions. *)
type kind = Typed_sql_ppx_cache.Query_cache.kind =
  | Select
  | Returning
  | Command
  | Unsupported

(** One described result column, in server-reported output order. *)
type field = Typed_sql_ppx_cache.Query_cache.field =
  { name : string (** Result-column name in the SQL output layout. *)
  ; typ : Type_info.postgresql_type_info
    (** Exact logical PostgreSQL type, with no database-specific OID. *)
  ; nullable : bool (** Whether decoding wraps the field value in an option. *)
  }

(** Exact rewritten SQL and ordered Prepare/Describe metadata. [None]
    means a command result; [Some] contains a nonempty result layout. *)
type entry = Typed_sql_ppx_cache.Query_cache.entry =
  { sql : string
    (** Exact SQL after rewriting OCaml substitutions to positional placeholders. *)
  ; kind : kind (** Statement category from the prepared metadata. *)
  ; top_level_only : bool (** Whether embedding must remain at the outer level. *)
  ; parameters : Type_info.postgresql_type_info list
    (** Parameter types in positional-placeholder order. *)
  ; result : field list option
    (** Absent for a command; otherwise a nonempty ordered output layout. *)
  }

(** Validated offline metadata for one role and search-path configuration. *)
type t

(** One cache describes one PostgreSQL role and configured search path.
    Entries contain logical types, never database-specific OIDs. Duplicate SQL,
    unsupported built-in codecs, custom type names unsuitable for OCaml converter
    identifiers, and zero-column row results are rejected. User-defined types
    select [PGOCaml.string_of_TYPENAME] and [PGOCaml.TYPENAME_of_string], including
    domains without unwrapping their base. Schemas do not qualify these functions;
    native arrays recursively select their element converter. *)
val create : role:string -> search_path:string -> entry list -> (t, string) Result.t

(** Decode version 3 query metadata and validate transport converters. *)
val of_string : string -> (t, string) Result.t

(** Serialize readable version 3 metadata with shared type definitions; no
    database OIDs or runtime parameter values are persisted. *)
val to_string : t -> string

(** Emit a module registering validated, embedded metadata. No JSON file is
    opened by the resulting PPX driver. *)
val codegen : t -> string

(** Resolve the exact rewritten SQL and attach the current OCaml expressions.
    Missing metadata is an error. *)
val plan : t -> Query_bind.t -> (Statement_plan.t, Query_bind.error) Result.t
