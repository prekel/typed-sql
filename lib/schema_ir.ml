open! Base

type db_type =
  | Bool
  | Int
  | Int64
  | Float
  | Text
  | Bytes
  | Date
  | Timestamp
  | Uuid
  | Unsupported of string

type column =
  { name : Identifier.t
  ; db_type : db_type
  ; nullable : bool
  ; default : string option
  ; generated : bool
  ; primary_key_position : int option
  }

type foreign_key =
  { columns : Identifier.t list
  ; referenced_schema : Identifier.t option
  ; referenced_table : Identifier.t
  ; referenced_columns : Identifier.t list
  }

type unique_constraint =
  { name : Identifier.t option
  ; columns : Identifier.t list
  }

type table =
  { schema : Identifier.t option
  ; name : Identifier.t
  ; columns : column list
  ; foreign_keys : foreign_key list
  ; unique_constraints : unique_constraint list
  }

type t = table list

let v tables = tables

let column ~name ~db_type ~nullable ?default ?(generated = false) ?primary_key_position ()
  =
  { name; db_type; nullable; default; generated; primary_key_position }
;;

let foreign_key ~columns ?referenced_schema ~referenced_table ~referenced_columns () =
  { columns; referenced_schema; referenced_table; referenced_columns }
;;

let unique_constraint ?name columns = { name; columns }

let table ?schema ~name ~columns ?(foreign_keys = []) ?(unique_constraints = []) () =
  { schema; name; columns; foreign_keys; unique_constraints }
;;

let tables schema = schema
let table_name (table : table) = table.name
let table_schema (table : table) = table.schema
let columns (table : table) = table.columns
let foreign_keys (table : table) = table.foreign_keys
let unique_constraints (table : table) = table.unique_constraints
let column_name (column : column) = column.name
let column_db_type (column : column) = column.db_type
let column_nullable (column : column) = column.nullable
let column_default (column : column) = column.default
let column_generated (column : column) = column.generated
let column_primary_key_position (column : column) = column.primary_key_position
let foreign_key_columns (foreign_key : foreign_key) = foreign_key.columns

let foreign_key_referenced_schema (foreign_key : foreign_key) =
  foreign_key.referenced_schema
;;

let foreign_key_referenced_table (foreign_key : foreign_key) =
  foreign_key.referenced_table
;;

let foreign_key_referenced_columns (foreign_key : foreign_key) =
  foreign_key.referenced_columns
;;

let unique_constraint_name (constraint_ : unique_constraint) = constraint_.name
let unique_constraint_columns (constraint_ : unique_constraint) = constraint_.columns
