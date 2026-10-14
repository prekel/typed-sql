open! Base

type t =
  | Scalar of string
  | Enum of string * string
  | Array of t

(** Domains use their exact base type for operator resolution and conversion. *)
val of_column : offset:int -> Typed_sql_schema.Schema_ir.column -> (t, Sql.error) Result.t

val of_info
  :  offset:int
  -> Typed_sql_schema.Schema_ir.postgresql_type_info
  -> (t, Sql.error) Result.t

val codec : t -> Codec.t
val equal : t -> t -> bool
val compatible : t -> t -> bool
val comparable : t -> bool
val text : t -> bool
val numeric : t -> bool

(** Common type for fixed IN lists, restricted to known built-in implicit
    numeric/text coercions and identical nominal types. *)
val common : t -> t -> t option
