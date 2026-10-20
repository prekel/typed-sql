open! Base

(** A string-decoding failure at a byte offset in the original SQL. *)
type error =
  { offset : int (** Zero-based byte offset of the failure in the original SQL. *)
  ; message : string (** Diagnostic explanation; not a machine-readable error code. *)
  }

(** Decode a quoted SQL string. [quote] points at the opening apostrophe.
    Newline-separated continuations use the first segment's escape mode. *)
val quoted : escape:bool -> string -> quote:int -> (string * int, error) Result.t

(** Recognize a complete dollar-quote opener before considering OCaml binds.
    Tags are case-sensitive and contain no dollar signs. *)
val dollar_opener : string -> int -> (string * int) option

(** Read a dollar-quoted body starting at [body], using the exact opener
    [delimiter]. Return decoded contents and the offset after the closing
    delimiter, or an error at [start] if it is unterminated. *)
val dollar
  :  string
  -> start:int
  -> delimiter:string
  -> body:int
  -> (string * int, error) Result.t
