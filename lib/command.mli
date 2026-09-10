open! Base

(** A deferred INSERT, UPDATE, or DELETE statement without returned rows. *)
type t

module Private : sig
  val create : Ast.command -> t
  val ast : t -> Ast.command
end
