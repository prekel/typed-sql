open! Base

(** Errors from schema introspection, separate from statement execution errors. *)
type error =
  | Unsupported_dialect of string
  | Schema of string
  | Caqti of Caqti.Error.t

val error_to_string : error -> string

(** Read application tables and constraints from a SQLite or PostgreSQL
    connection. Unknown SQL types remain
    [Typed_sql_schema.Schema_ir.Unsupported]. Both dialects include ordinary
    unique column indexes and omit partial and expression indexes. PostgreSQL
    INCLUDE columns are not unique keys. SQLite hidden virtual-table columns
    are omitted; generated columns are retained. SQLite TIME remains
    unsupported. *)
val introspect
  :  conn:Caqti_lwt.connection
  -> (Typed_sql_schema.Schema_ir.t, error) Result.t Lwt.t
