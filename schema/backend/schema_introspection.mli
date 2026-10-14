open! Base

type error = Schema of string

type raw_column =
  string option * string * string * (string * bool * string option * (bool * int option))

type raw_foreign_key =
  string option
  * string
  * string option
  * (int * string * string option * (string * string option))

type raw_unique = string option * string * string option * (int * string)
type raw_attribute = string * string * string * bool
type raw_type = int * string * string * (string * int * int * string)

(** Shared PostgreSQL catalog queries keep both drivers' snapshots aligned. *)
val postgresql_columns : string

val postgresql_types : string
val postgresql_attributes : string
val postgresql_foreign_keys : string
val postgresql_uniques : string
val sqlite_db_type : string -> Typed_sql_schema.Schema_ir.db_type
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

val postgresql_attribute_not_null
  :  raw_attribute list
  -> string option
  -> string
  -> string
  -> bool option

val make_schema
  :  ?postgresql_type:(string -> (Typed_sql.Identifier.t * Typed_sql.Identifier.t) option)
  -> ?postgresql_type_info:
       (string
        -> (Typed_sql_schema.Schema_ir.postgresql_type_info option, error) Result.t)
  -> ?postgresql_attribute_not_null:(string option -> string -> string -> bool option)
  -> db_type:(string -> Typed_sql_schema.Schema_ir.db_type)
  -> raw_column list
  -> raw_foreign_key list
  -> raw_unique list
  -> (Typed_sql_schema.Schema_ir.t, error) Result.t
