open! Base

(** The result of validation, normalization, lowering and parameter
    extraction. The query remains independent from an execution backend. *)
type 'result t

val dialect : 'result t -> Dialect.t
val template : 'result t -> Template.t
val parameters : 'result t -> Db_type.packed_value list
val projection : 'result t -> 'result Projection.t
val shape : 'result t -> Shape.t
val sql : 'result t -> string

module Private : sig
  val create
    :  dialect:Dialect.t
    -> template:Template.t
    -> parameters:Db_type.packed_value list
    -> projection:'result Projection.t
    -> shape:Shape.t
    -> 'result t
end
