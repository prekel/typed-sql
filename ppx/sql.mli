open! Base

type error =
  { offset : int
  ; message : string
  }

type reference =
  { names : string list
  ; offset : int
  }

type parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type projection =
  | Column of reference * string option
  | All of reference

type t =
  { source : string
  ; schema : string
  ; table : string
  ; alias : string option
  ; projection : projection list
  ; conditions : (reference * parameter) list
  ; order : reference list
  }

(** Parse only the supported single-table SELECT grammar. Every token must be
    consumed. Offsets refer to bytes in the SQL literal, not the OCaml file. *)
val parse : string -> (t, error) Result.t

val error_to_string : error -> string
