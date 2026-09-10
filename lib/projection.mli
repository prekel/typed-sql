open! Base

(** An applicative description of SELECT expressions and their result
    decoder. A standalone [pure] projection is rejected because SQL SELECT must
    contain at least one expression. *)
type 'a t

type _ view =
  | Pure : 'a -> 'a view
  | Expr : 'a Expr.t -> 'a view
  | Map : ('a -> 'b) * 'a t -> 'b view
  | Both : 'a t * 'b t -> ('a * 'b) view

val pure : 'a -> 'a t
val expr : 'a Expr.t -> 'a t
val map : ('a -> 'b) -> 'a t -> 'b t
val both : 'a t -> 'b t -> ('a * 'b) t
val map2 : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
val map3 : ('a -> 'b -> 'c -> 'd) -> 'a t -> 'b t -> 'c t -> 'd t
val view : 'a t -> 'a view

module Private : sig
  val expressions : 'a t -> Ast.expr list
  val types : 'a t -> Db_type.packed list
end
