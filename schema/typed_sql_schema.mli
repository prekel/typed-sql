open! Base
module Identifier = Typed_sql.Identifier

(** Dialect-neutral metadata used by schema introspection and code generation. *)
module Schema_ir : sig
  (** Portable column representations known to the generator. [Unsupported]
      preserves a database type name so introspection never guesses a codec. *)
  type db_type =
    | Bool
    | Int
    | Int64
    | Float
    | Numeric
    | Text
    | Bytes
    | Date
    | Timestamp
    | Timestamp_without_timezone
    | Interval
    | Json
    | Jsonb
    | Uuid
    | Enum of
        { schema : Identifier.t
        ; name : Identifier.t
        ; labels : string list
        }
    | Domain of
        { schema : Identifier.t
        ; name : Identifier.t
        ; base : db_type
        }
    | Array of db_type
    | Named of
        { schema : Identifier.t
        ; name : Identifier.t
        }
    | Unsupported of string

  (** Exact nested native types, independent of portable DSL representations. *)
  type postgresql_type_info =
    { schema : Identifier.t
    ; name : Identifier.t
    ; kind : postgresql_type_kind
    }

  and postgresql_type_kind =
    | Native_scalar
    | Native_enum of string list
    | Native_domain of postgresql_type_info
    | Native_array of postgresql_type_info
    | Native_opaque

  type column
  type foreign_key
  type unique_constraint
  type table
  type t

  (** Construct a schema from tables in dependency-independent declaration
      order. *)
  val v : table list -> t

  (** Describe one column, including metadata that affects generated
      descriptors and migrations. Default expressions remain opaque metadata
      and are never inserted into query SQL. *)
  val column
    :  name:Identifier.t
    -> db_type:db_type
    -> nullable:bool
    -> ?default:string
    -> ?generated:bool
    -> ?primary_key_position:int
    -> ?postgresql_type:Identifier.t * Identifier.t
    -> ?postgresql_type_info:postgresql_type_info
    -> ?postgresql_attribute_not_null:bool
    -> ?postgresql_type_modifier:int
    -> unit
    -> column

  (** Describe a possibly composite foreign key. Column lists use declaration
      order on both sides. *)
  val foreign_key
    :  columns:Identifier.t list
    -> ?referenced_schema:Identifier.t
    -> referenced_table:Identifier.t
    -> referenced_columns:Identifier.t list
    -> unit
    -> foreign_key

  (** Describe a possibly named unique column set. *)
  val unique_constraint : ?name:Identifier.t -> Identifier.t list -> unique_constraint

  (** Describe one table and its relational constraints. *)
  val table
    :  ?schema:Identifier.t
    -> name:Identifier.t
    -> columns:column list
    -> ?foreign_keys:foreign_key list
    -> ?unique_constraints:unique_constraint list
    -> ?postgresql_primary_key_deferrable:bool
    -> unit
    -> table

  (** Return tables in introspection or declaration order. *)
  val tables : t -> table list

  (** Return the unqualified table name. *)
  val table_name : table -> Identifier.t

  (** Return the schema qualifier when the database supplied one. *)
  val table_schema : table -> Identifier.t option

  (** Return columns in ordinal order. *)
  val columns : table -> column list

  (** Return declared foreign keys. *)
  val foreign_keys : table -> foreign_key list

  (** Return primary-key-independent unique constraints. *)
  val unique_constraints : table -> unique_constraint list

  (** Native PK deferrability. [None] means absent PK or missing metadata;
      only [Some false] proves eligibility for PostgreSQL GROUP BY dependency. *)
  val postgresql_primary_key_deferrable : table -> bool option

  (** Return the SQL column name. *)
  val column_name : column -> Identifier.t

  (** Return the portable or preserved unsupported database type. *)
  val column_db_type : column -> db_type

  (** Exact PostgreSQL [(schema, type_name)] when introspection supplied it.
      Unlike [column_db_type], this distinguishes [int2] from [int4]. Older
      snapshots and SQLite columns return [None]; missing metadata must not
      be reconstructed from the portable representation. *)
  val column_postgresql_type : column -> (Identifier.t * Identifier.t) option

  (** Optional exact type tree. Older version 3 snapshots omit this extension. *)
  val column_postgresql_type_info : column -> postgresql_type_info option

  (** Native attribute flag used by PG'OCaml's direct-column NULL heuristic,
      independent of domain-level constraints. *)
  val column_postgresql_attribute_not_null : column -> bool option

  (** Raw [pg_attribute.atttypmod]. [Some (-1)] means no declared modifier;
      [None] means metadata was not recorded. *)
  val column_postgresql_type_modifier : column -> int option

  (** Report whether reads use an option codec. *)
  val column_nullable : column -> bool

  (** Return the database default expression as opaque metadata. *)
  val column_default : column -> string option

  (** Report whether the database generates the column. *)
  val column_generated : column -> bool

  (** Return the one-based position inside a composite primary key. *)
  val column_primary_key_position : column -> int option

  (** Return referencing columns in key order. *)
  val foreign_key_columns : foreign_key -> Identifier.t list

  (** Return the referenced schema qualifier when the database supplied one. *)
  val foreign_key_referenced_schema : foreign_key -> Identifier.t option

  (** Return the unqualified referenced table. *)
  val foreign_key_referenced_table : foreign_key -> Identifier.t

  (** Return referenced columns in key order. *)
  val foreign_key_referenced_columns : foreign_key -> Identifier.t list

  (** Return the database constraint name when available. *)
  val unique_constraint_name : unique_constraint -> Identifier.t option

  (** Return unique columns in key order. *)
  val unique_constraint_columns : unique_constraint -> Identifier.t list
end

(** Persist schema metadata for offline descriptor generation. *)
module Schema_snapshot : sig
  (** A malformed document or unsupported snapshot version. *)
  type error

  (** Encode version 3 JSON with a fixed field order, indentation and a final
      newline. All schema list orders and opaque default/type strings are
      preserved. Original optional metadata is written as JSON [null]; the new
      version 3 extension fields are omitted when absent. No database or
      filesystem access is performed. *)
  val to_string : Schema_ir.t -> string

  (** Decode a version 2 or 3 JSON document. Version 2 has no exact PostgreSQL
      type metadata. The original fields for each declared version are required; version 3 also
      accepts optional native type trees and attribute NULL flags; duplicate
      and unknown fields, invalid identifiers, incorrect JSON types and
      unsupported versions are rejected. This validates the snapshot structure,
      not database constraints or whether the generator supports its SQL types. *)
  val of_string : string -> (Schema_ir.t, error) Result.t

  (** Explain the error with a JSON field path, or [$] for a syntax error. *)
  val error_to_string : error -> string
end

(** Generate table, column, accessor and projection descriptors as OCaml source. *)
module Schema_codegen : sig
  type error =
    | Empty_table of Identifier.t
    | Unsupported_type of
        { table : Identifier.t
        ; column : Identifier.t
        ; database_type : string
        }
    | Invalid_rules of string

  type rule

  (** Parse ordered generator rules. Each rule has [priority], [sql_type],
      [column], and [module] fields; at least one filter must be present.
      Filters are full-match regular expressions. The owning column name is
      retained when matching array element types, so a column-specific rule
      can select an element codec without replacing the array representation. *)
  val rules_of_string : string -> (rule list, string) Result.t

  (** Explain why descriptor source could not be generated. *)
  val error_to_string : error -> string

  (** Generate modules in schema order. Names are normalized to valid OCaml
      identifiers; SQL names remain unchanged in quoted string literals.
      Normalized names that collide with another generated binding or a
      generator-owned binding receive deterministic [_2], [_3], ... suffixes
      in schema order. The returned source opens [Base] and [Typed_sql] and can
      be compiled directly as a module with [ppx_let]. Each table module
      retains column defaults, generated and primary-key flags, foreign keys,
      and unique constraints as ordinary metadata values. *)
  val generate : ?rules:rule list -> Schema_ir.t -> (string, error) Result.t

  (** Generate OCaml source that constructs the complete schema value and
      registers it with [typed-sql-pgocaml-ppx]. The returned module is loaded
      into the PPX driver through Dune's [pps] mechanism. *)
  val generate_pgocaml_ppx : Schema_ir.t -> string
end
