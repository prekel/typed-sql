open! Base

(** An immutable deferred SELECT query. ['ctx] is the callback context of
    visible table references and ['result] is the decoded row type. *)
type ('ctx, 'result) t

type direction =
  [ `Asc
  | `Desc
  ]

val from
  :  'row Table.t
  -> select:('row Table_ref.t -> 'result Projection.t)
  -> ('row Table_ref.t, 'result) t

val select : ('ctx -> 'result Projection.t) -> ('ctx, 'old_result) t -> ('ctx, 'result) t
val where : ('ctx -> Condition.t) -> ('ctx, 'result) t -> ('ctx, 'result) t

val where_opt
  :  'value option
  -> f:('ctx -> 'value -> Condition.t)
  -> ('ctx, 'result) t
  -> ('ctx, 'result) t

val order_by
  :  ('ctx -> 'value Expr.t)
  -> direction
  -> ('ctx, 'result) t
  -> ('ctx, 'result) t

val limit : int -> ('ctx, 'result) t -> ('ctx, 'result) t
val offset : int -> ('ctx, 'result) t -> ('ctx, 'result) t

module Private : sig
  val ast : ('ctx, 'result) t -> Ast.select
  val projection : ('ctx, 'result) t -> 'result Projection.t
end
