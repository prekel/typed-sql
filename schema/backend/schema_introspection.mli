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
type raw_type = int * string * string * (string * int * int * string)

(** Shared PostgreSQL catalog queries keep both drivers' snapshots aligned. *)
val postgresql_columns : string

val postgresql_types : string
val postgresql_foreign_keys : string
val postgresql_uniques : string
val sqlite_db_type : string -> Typed_sql_schema.Schema_ir.db_type
val postgresql_type_mapper : raw_type list -> string -> Typed_sql_schema.Schema_ir.db_type

val make_schema
  :  db_type:(string -> Typed_sql_schema.Schema_ir.db_type)
  -> raw_column list
  -> raw_foreign_key list
  -> raw_unique list
  -> (Typed_sql_schema.Schema_ir.t, error) Result.t
