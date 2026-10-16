open! Base

type error =
  { offset : int
  ; message : string
  }

type parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type t =
  { sql : string
  ; parameters : parameter list
  }

(** Scan OCaml substitutions without parsing SQL expressions or inferring types.
    SQL identifiers, quoting and comments are preserved verbatim. *)
val scan : string -> (t, error) Result.t

(** Recognize a PostgreSQL dollar quote at a token boundary. *)
val dollar_opener : string -> int -> (string * int) option
