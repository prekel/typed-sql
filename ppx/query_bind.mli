open! Base

(** Rewritten SQL and one bind occurrence per positional placeholder.
    Parameters retain source spans in the original quotation. *)
type t =
  { sql : string
    (** SQL rewritten to positional placeholders; OCaml values stay separate. *)
  ; parameters : Sql.parameter list (** Bind occurrences in SQL/source order. *)
  }

(** Rewrite only OCaml substitutions, preserving all other SQL bytes. Each
    occurrence gets its own positional parameter. SQL is not parsed or typed.
    Native positional parameters and dynamic list substitutions are rejected. *)
val scan : string -> (t, Sql.error) Result.t
