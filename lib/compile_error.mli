open! Base

type t =
  | Empty_projection
  | Foreign_source of
      { expected : int
      ; actual : int
      }
  | Negative_limit of int
  | Negative_offset of int

val pp : Formatter.t -> t -> unit
val to_string : t -> string
