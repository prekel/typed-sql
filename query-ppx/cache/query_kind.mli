open! Base

type operation =
  | Select
  | Insert
  | Update
  | Delete
  | Unsupported

type t =
  { operation : operation
  ; top_level_only : bool
  ; terminator : int option
  }

(** Classify the outside command and WITH bodies after PostgreSQL has accepted
    the SQL. This is not SQL validation or inference. Unknown CTE syntax and
    utility commands remain Unsupported. Outer row locks and data-modifying CTEs
    require top-level placement; row locks in nested SELECTs do not restrict the
    enclosing SELECT. [terminator] locates a final semicolon
    outside strings and comments in the rewritten SQL. *)
val analyze : string -> t
