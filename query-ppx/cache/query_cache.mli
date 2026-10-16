open! Base
module Type_info = Typed_sql_schema.Schema_ir

type kind =
  | Select
  | Returning
  | Command
  | Unsupported

type field =
  { name : string
  ; typ : Type_info.postgresql_type_info
  ; nullable : bool
  }

type entry =
  { sql : string
  ; kind : kind
  ; top_level_only : bool
  ; parameters : Type_info.postgresql_type_info list
  ; result : field list option
  }

type t

(** Logical metadata only; no driver or PGOCaml codec is used here. *)
val create : role:string -> search_path:string -> entry list -> (t, string) Result.t

val entries : t -> entry list
val find : t -> sql:string -> entry option
val kind : operation:Query_kind.operation -> rows:bool -> kind
val kind_to_string : kind -> string

(** v1 remains readable with Unsupported kind, requiring refresh for query PPX. *)
val of_string : string -> (t, string) Result.t

val to_string : t -> string
val codegen : target:[ `Pgocaml_ppx | `Typed_sql_ppx ] -> t -> string
