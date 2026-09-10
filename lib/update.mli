open! Base

type unscoped
type scoped
type ('row, 'scope) t

val table : 'row Table.t -> ('row, unscoped) t
val set : ('row, 'base, 'value) Column.t -> 'value -> ('row, 'scope) t -> ('row, 'scope) t

val set_expr
  :  ('row, 'base, 'value) Column.t
  -> 'value Expr.t
  -> ('row, 'scope) t
  -> ('row, 'scope) t

val where : ('row Table_ref.t -> Condition.t) -> ('row, 'scope) t -> ('row, scoped) t

(** Explicitly authorize updating every row. *)
val all_rows : ('row, 'scope) t -> ('row, scoped) t

val command : ('row, scoped) t -> Command.t

val returning
  :  ('row Table_ref.t -> 'result Projection.t)
  -> ('row, scoped) t
  -> 'result Result_query.t
