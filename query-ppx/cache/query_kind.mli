open! Base

(** Recognized outer SQL operations. Unrecognized utility commands remain unsupported. *)
type operation =
  | Select (** An outer SELECT, including a supported WITH prefix. *)
  | Insert (** An outer INSERT. *)
  | Update (** An outer UPDATE. *)
  | Delete (** An outer DELETE. *)
  | Unsupported (** An unrecognized operation or unsupported CTE syntax. *)

(** Placement information for server-accepted SQL. [terminator], when
    present, is the byte offset of the final outer semicolon in rewritten SQL. *)
type t =
  { operation : operation
    (** Recognized outer operation, without inferring SQL expression types. *)
  ; top_level_only : bool
    (** True when outer row locks or modifying CTEs forbid nesting. *)
  ; terminator : int option
    (** Byte offset of a final outer semicolon in rewritten SQL, if present. *)
  }

(** Classify the outside command and WITH bodies after PostgreSQL has accepted
    the SQL. Unknown CTE syntax and
    utility commands remain Unsupported. Outer row locks and data-modifying CTEs
    require top-level placement; row locks in nested SELECTs do not restrict the
    enclosing SELECT. [terminator] locates a final semicolon
    outside strings and comments in the rewritten SQL. *)
val analyze : string -> t
