open! Base

(** Source byte offsets and diagnostics from substitution scanning or cache lookup. *)
type error = Typed_sql_ppx_cache.Query_bind.error =
  { offset : int
  ; message : string
  }

type parameter = Typed_sql_ppx_cache.Query_bind.parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type t = Typed_sql_ppx_cache.Query_bind.t =
  { sql : string
  ; parameters : parameter list
  }

(** Rewrite OCaml substitutions to numbered parameters, preserving SQL bytes.
    Each occurrence retains its OCaml expression and source span; values are
    never evaluated here. Dynamic lists and native positional parameters fail. *)
val scan : string -> (t, error) Result.t

(** Format the source byte offset and diagnostic message. *)
val error_to_string : error -> string
