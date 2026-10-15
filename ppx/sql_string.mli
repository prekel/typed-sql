open! Base

type error =
  { offset : int
  ; message : string
  }

(** Decode a quoted SQL string. [quote] points at the opening apostrophe.
    Newline-separated continuations use the first segment's escape mode. *)
val quoted : escape:bool -> string -> quote:int -> (string * int, error) Result.t

(** Recognize a complete dollar-quote opener before considering OCaml binds.
    Tags are case-sensitive and contain no dollar signs. *)
val dollar_opener : string -> int -> (string * int) option

val dollar
  :  string
  -> start:int
  -> delimiter:string
  -> body:int
  -> (string * int, error) Result.t
