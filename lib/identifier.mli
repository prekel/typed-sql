open! Base

(** A validated, unquoted SQL identifier. Renderers are responsible for
    dialect-specific quoting. *)
type t

type error =
  [ `Empty
  | `Contains_nul
  ]

val of_string : string -> (t, error) Result.t
val of_string_exn : string -> t
val to_string : t -> string
val equal : t -> t -> bool
val pp : Formatter.t -> t -> unit
val error_to_string : error -> string
