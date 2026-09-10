open! Base

type unscoped
type scoped
type ('row, 'scope) t

val from : 'row Table.t -> ('row, unscoped) t
val where : ('row Table_ref.t -> Condition.t) -> ('row, 'scope) t -> ('row, scoped) t

(** Explicitly authorize deleting every row. *)
val all_rows : ('row, 'scope) t -> ('row, scoped) t

val command : ('row, scoped) t -> Command.t

val returning
  :  ('row Table_ref.t -> 'result Projection.t)
  -> ('row, scoped) t
  -> 'result Result_query.t
