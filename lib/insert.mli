open! Base

(** A single-row INSERT builder. *)
type 'row t

val into : 'row Table.t -> 'row t
val set : ('row, 'base, 'value) Column.t -> 'value -> 'row t -> 'row t
val set_expr : ('row, 'base, 'value) Column.t -> 'value Expr.t -> 'row t -> 'row t
val command : 'row t -> Command.t

val returning
  :  ('row Table_ref.t -> 'result Projection.t)
  -> 'row t
  -> 'result Result_query.t
