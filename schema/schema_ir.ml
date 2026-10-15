open! Base
module Identifier = Typed_sql.Identifier

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

type column =
  { name : Identifier.t
  ; db_type : db_type
  ; nullable : bool
  ; default : string option
  ; generated : bool
  ; primary_key_position : int option
  ; postgresql_type : (Identifier.t * Identifier.t) option
  ; postgresql_type_info : postgresql_type_info option
  ; postgresql_attribute_not_null : bool option
  ; postgresql_type_modifier : int option
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

let column
      ~name
      ~db_type
      ~nullable
      ?default
      ?(generated = false)
      ?primary_key_position
      ?postgresql_type
      ?postgresql_type_info
      ?postgresql_attribute_not_null
      ?postgresql_type_modifier
      ()
  =
  { name
  ; db_type
  ; nullable
  ; default
  ; generated
  ; primary_key_position
  ; postgresql_type
  ; postgresql_type_info
  ; postgresql_attribute_not_null
  ; postgresql_type_modifier
  }
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
let column_postgresql_type (column : column) = column.postgresql_type
let column_postgresql_type_info (column : column) = column.postgresql_type_info

let column_postgresql_attribute_not_null (column : column) =
  column.postgresql_attribute_not_null
;;

let column_postgresql_type_modifier (column : column) = column.postgresql_type_modifier
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
