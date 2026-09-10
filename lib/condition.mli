open! Base

(** A predicate using SQL three-valued logic. *)
type t

val true_ : t
val false_ : t
val and_ : t -> t -> t
val or_ : t -> t -> t
val not_ : t -> t
val all : t list -> t
val any : t list -> t

module Infix : sig
  val ( &&. ) : t -> t -> t
  val ( ||. ) : t -> t -> t
end

module Private : sig
  val create : Ast.condition -> t
  val node : t -> Ast.condition
end
