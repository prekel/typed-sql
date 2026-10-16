open! Base

type t =
  { query : Query_bind.t
  ; loc : Ppxlib.Location.t
  }

(** Decode a legacy or typed SQL quotation; no code is evaluated. *)
val payload_exn
  :  loc:Ppxlib.Location.t
  -> legacy:bool
  -> Ppxlib.payload
  -> string list * string * Ppxlib.Location.t

(** Decode a statement quotation with an optional runtime input pattern. *)
val statement_payload_exn
  :  loc:Ppxlib.Location.t
  -> Ppxlib.payload
  -> Ppxlib.pattern option * string list * string * Ppxlib.Location.t

val collect_exn : Ppxlib.structure -> t list
