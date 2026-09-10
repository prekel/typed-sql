open! Base

(** A normalized query-compilation identity. Parameter values and generative
    source identities are excluded. *)
type t

val equal : t -> t -> bool
val hash : t -> int
val pp : Formatter.t -> t -> unit
val to_string : t -> string

module Private : sig
  val create : string -> t
end
