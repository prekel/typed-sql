open! Base

(** A scanned quotation and source location used to report collection failures. *)
type t =
  { query : Query_bind.t
    (** Scanned literal with rewritten SQL and source substitutions. *)
  ; loc : Ppxlib.Location.t
    (** Original quotation location for located PPX diagnostics. *)
  }

(** Decode a connection-based or typed SQL quotation; no code is evaluated. *)
val payload_exn
  :  loc:Ppxlib.Location.t
  -> with_connection:bool
  -> Ppxlib.payload
  -> string list * string * Ppxlib.Location.t

(** Decode a statement quotation with an optional runtime input pattern. *)
val statement_payload_exn
  :  loc:Ppxlib.Location.t
  -> Ppxlib.payload
  -> Ppxlib.pattern option * string list * string * Ppxlib.Location.t

(** Collect literal connection-based and typed quotations from an OCaml structure.
    No code is evaluated; malformed payloads raise located PPX errors. *)
val collect_exn : Ppxlib.structure -> t list
