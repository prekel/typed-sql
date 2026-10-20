open! Base

(** Invalid identifiers or inconsistent catalog metadata encountered during assembly. *)
type error =
  | Schema of string
  (** Catalog metadata could not be assembled into a valid schema snapshot. *)

(** [(schema, table, column, (type, nullable, default, (generated, pk_position)))].
    The type string is a declared SQLite type or PostgreSQL OID; primary-key
    positions are one-based and default expressions remain opaque. *)
type raw_column =
  string option * string * string * (string * bool * string option * (bool * int option))

(** [(schema, table, constraint_name, (position, column, referenced_schema,
    (referenced_table, referenced_column)))]. Rows of one key must be adjacent
    and ordered by key position. Missing referenced columns use the target primary key. *)
type raw_foreign_key =
  string option
  * string
  * string option
  * (int * string * string option * (string * string option))

(** [(schema, table, constraint_name, (position, column))], adjacent and
    ordered by position for each unique key. *)
type raw_unique = string option * string * string option * (int * string)

(** [(schema, table, column, (not_null, type_modifier, pk_deferrable))].
    The last flag is absent when no primary key was reported. *)
type raw_attribute = string * string * string * (bool * int * bool option)

(** [(oid, schema, name, (kind, base_oid, element_oid, enum_labels_json))].
    OIDs are used only to resolve a catalog read and are not persisted in snapshots. *)
type raw_type = int * string * string * (string * int * int * string)

(** Shared PostgreSQL catalog queries keep both drivers' snapshots aligned. *)
val postgresql_columns : string

(** Catalog query for native type identities, domains, arrays and enum labels. *)
val postgresql_types : string

(** Catalog query for native NOT NULL, raw type modifiers and PK deferrability. *)
val postgresql_attributes : string

(** Catalog query for foreign-key columns ordered by constraint and key position. *)
val postgresql_foreign_keys : string

(** Catalog query for valid ordinary unique keys, excluding primary keys,
    partial/expression indexes and INCLUDE columns. *)
val postgresql_uniques : string

(** Map a SQLite declared type using the supported affinity/name rules.
    Unrecognized declarations, including TIME, remain unsupported. *)
val sqlite_db_type : string -> Typed_sql_schema.Schema_ir.db_type

(** Build a PostgreSQL OID-to-logical-type resolver from one catalog read.
    Unknown and recursive types remain unsupported rather than guessing a codec. *)
val postgresql_type_mapper : raw_type list -> string -> Typed_sql_schema.Schema_ir.db_type

(** Resolve the exact catalog name without losing portable type distinctions. *)
val postgresql_column_type
  :  raw_type list
  -> string
  -> (Typed_sql.Identifier.t * Typed_sql.Identifier.t) option

(** Resolve nested exact types; malformed/cyclic catalog rows are errors. *)
val postgresql_type_info
  :  raw_type list
  -> string
  -> (Typed_sql_schema.Schema_ir.postgresql_type_info option, error) Result.t

(** Look up the native column NOT NULL flag by exact schema/table/column
    name. Missing schema or metadata returns [None]. *)
val postgresql_attribute_not_null
  :  raw_attribute list
  -> string option
  -> string
  -> string
  -> bool option

(** Raw column type modifier, without guessing absent metadata. *)
val postgresql_type_modifier
  :  raw_attribute list
  -> string option
  -> string
  -> string
  -> int option

(** Native table PK deferrability from shared catalog rows. *)
val postgresql_primary_key_deferrable
  :  raw_attribute list
  -> string option
  -> string
  -> bool option

(** Assemble ordered tables and constraints, validating identifiers and
    resolving implicit foreign-key targets through primary keys. Column rows
    must be adjacent per table; constraint rows must be adjacent per key in
    column order. Optional callbacks enrich PostgreSQL metadata; omitted
    callbacks preserve its absence. *)
val make_schema
  :  ?postgresql_type:(string -> (Typed_sql.Identifier.t * Typed_sql.Identifier.t) option)
  -> ?postgresql_type_info:
       (string
        -> (Typed_sql_schema.Schema_ir.postgresql_type_info option, error) Result.t)
  -> ?postgresql_attribute_not_null:(string option -> string -> string -> bool option)
  -> ?postgresql_type_modifier:(string option -> string -> string -> int option)
  -> ?postgresql_primary_key_deferrable:(string option -> string -> bool option)
  -> db_type:(string -> Typed_sql_schema.Schema_ir.db_type)
  -> raw_column list
  -> raw_foreign_key list
  -> raw_unique list
  -> (Typed_sql_schema.Schema_ir.t, error) Result.t
