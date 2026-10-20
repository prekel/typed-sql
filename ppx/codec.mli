open! Base

(** PG'OCaml converter names and recursively nested array codecs. Scalar
    names select conversion functions, rather than SQL type identifiers. *)
type t =
  | Scalar of string (** PG'OCaml converter stem, such as [int32] or [string]. *)
  | Array of t (** Array conversion using the nested element converter. *)

(** Diagnostic representation, not a PostgreSQL type name. *)
val to_string : t -> string
