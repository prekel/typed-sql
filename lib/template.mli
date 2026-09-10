open! Base

(** A backend-neutral SQL template. [Text] fragments are produced only by the
    compiler; [Param] fragments are zero-based bind slots. *)
type part =
  | Text of string
  | Param of int

type t

val parts : t -> part list
val to_sql : dialect:Dialect.t -> t -> string

module Private : sig
  val of_parts : part list -> t
  val shape_string : t -> string
end
