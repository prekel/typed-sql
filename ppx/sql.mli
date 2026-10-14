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

type value =
  | Bind of parameter
  | Default of int
  | Excluded of reference

type assignment = reference * value

type conflict_action =
  | Do_nothing
  | Do_update of assignment list * (reference * parameter) list

type conflict =
  { target : reference list option
  ; action : conflict_action
  }

type statement =
  | Select
  | Insert of
      { columns : reference list
      ; rows : value list list option
      ; conflict : conflict option
      }
  | Update of assignment list
  | Delete

type t =
  { source : string
  ; schema : string
  ; table : string
  ; alias : string option
  ; statement : statement
  ; projection : projection list
  ; conditions : (reference * parameter) list
  ; order : reference list
  }

(** Parse the supported single-table SELECT and DML grammar. Every token must
    be consumed. Offsets refer to bytes in the SQL literal, not the OCaml file. *)
val parse : string -> (t, error) Result.t

val error_to_string : error -> string
