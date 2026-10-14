open! Base

type t =
  | Scalar of string
  | Array of t

(** Diagnostic representation, not a PostgreSQL type name. *)
val to_string : t -> string
