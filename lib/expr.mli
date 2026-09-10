open! Base

(** A typed scalar SQL expression. *)
type 'a t

val column : 'row Table_ref.t -> ('row, 'a) Column.t -> 'a t
val param : 'a Db_type.t -> 'a -> 'a t
val eq : 'a t -> 'a t -> Condition.t
val eq_value : 'a t -> 'a -> Condition.t
val neq : 'a t -> 'a t -> Condition.t
val neq_value : 'a t -> 'a -> Condition.t
val lt : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
val lt_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
val lte : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
val lte_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
val gt : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
val gt_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
val gte : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
val gte_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
val like : string t -> string t -> Condition.t
val like_value : string t -> string -> Condition.t
val is_null : 'a option t -> Condition.t
val is_not_null : 'a option t -> Condition.t
val db_type : 'a t -> 'a Db_type.t

module Infix : sig
  val ( =. ) : 'a t -> 'a t -> Condition.t
  val ( =: ) : 'a t -> 'a -> Condition.t
  val ( <>. ) : 'a t -> 'a t -> Condition.t
  val ( <>: ) : 'a t -> 'a -> Condition.t
end

module Private : sig
  val node : 'a t -> Ast.expr
end
