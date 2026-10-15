open! Base

type t =
  { sql : string
  ; parameters : Sql.parameter list
  }

(** Rewrite only OCaml substitutions, preserving all other SQL bytes. Each
    occurrence gets its own positional parameter. SQL is not parsed or typed.
    Native positional parameters and dynamic list substitutions are rejected. *)
val scan : string -> (t, Sql.error) Result.t
