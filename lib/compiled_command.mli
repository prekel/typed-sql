open! Base

(** A compiled statement without a row decoder. *)
type t

val dialect : t -> Dialect.t
val template : t -> Template.t
val parameters : t -> Db_type.packed_value list
val shape : t -> Shape.t
val sql : t -> string

module Private : sig
  val create
    :  dialect:Dialect.t
    -> template:Template.t
    -> parameters:Db_type.packed_value list
    -> shape:Shape.t
    -> t
end
