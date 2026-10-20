open! Base

(** A substitution scanning failure at a zero-based source byte offset. *)
type error =
  { offset : int (** Zero-based byte offset of the failure in the original SQL. *)
  ; message : string (** Diagnostic explanation; not a machine-readable error code. *)
  }

(** One OCaml expression with its nullable-conversion flag and source
    span. [start] is inclusive and [stop] exclusive in the original quotation. *)
type parameter =
  { expression : string
    (** OCaml expression text to splice into generated binding code. *)
  ; optional : bool (** Whether the substitution uses nullable conversion. *)
  ; start : int (** Inclusive source byte offset of the substitution. *)
  ; stop : int (** Exclusive source byte offset of the substitution. *)
  }

(** SQL rewritten to positional parameters and source-ordered bind occurrences. *)
type t =
  { sql : string
    (** SQL rewritten to positional placeholders; OCaml values stay separate. *)
  ; parameters : parameter list (** Bind occurrences in SQL/source order. *)
  }

(** Scan OCaml substitutions without parsing SQL expressions or inferring types.
    SQL identifiers, quoting and comments are preserved verbatim. *)
val scan : string -> (t, error) Result.t

(** Recognize a PostgreSQL dollar quote at a token boundary. *)
val dollar_opener : string -> int -> (string * int) option
