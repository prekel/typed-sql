open! Base

type t =
  | Empty_projection
  | Foreign_source of
      { visible : int list
      ; actual : int
      }
  | Negative_limit of int
  | Negative_offset of int
  | Empty_assignments of [ `Insert | `Update ]
  | Duplicate_assignment of Identifier.t
  | Invalid_assignment_source of
      { expected : int
      ; actual : int
      }

val pp : Formatter.t -> t -> unit
val to_string : t -> string
