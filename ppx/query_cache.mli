open! Base
module Type_info = Typed_sql_schema.Schema_ir

type field =
  { name : string
  ; typ : Type_info.postgresql_type_info
  ; nullable : bool
  }

type entry =
  { sql : string
  ; parameters : Type_info.postgresql_type_info list
  ; result : field list option
  }

type t

(** One cache describes one PostgreSQL role and configured search path.
    Entries contain logical types, never database-specific OIDs. Duplicate SQL,
    unsupported codecs and zero-column row results are rejected. *)
val create : role:string -> search_path:string -> entry list -> (t, string) Result.t

val of_string : string -> (t, string) Result.t
val to_string : t -> string

(** Emit a module registering validated, embedded metadata. No JSON file is
    opened by the resulting PPX driver. *)
val codegen : t -> string

(** Resolve the exact rewritten SQL and attach the current OCaml expressions.
    Missing metadata is an error; no database or schema-inference fallback runs. *)
val plan : t -> Query_bind.t -> (Statement_plan.t, Sql.error) Result.t
