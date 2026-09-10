open! Base

(** A deferred statement that returns decoded rows. *)
type 'result t

module Private : sig
  val create : Ast.result_query -> 'result Projection.t -> 'result t
  val ast : 'result t -> Ast.result_query
  val projection : 'result t -> 'result Projection.t
end
