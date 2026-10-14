open! Base

(** One-dimensional PostgreSQL text arrays. Elements are always quoted and
    escaped independently of SQL literal syntax. *)
val string_of_array : ('a -> string) -> 'a option list -> string

(** Parse the wire representation, retaining the distinction between an
    unquoted NULL element and the quoted string "NULL". Explicit bounds and
    nested dimensions return an error. Scalar conversion belongs to PGOCaml. *)
val array_of_string : string -> (string option list, string) Result.t
