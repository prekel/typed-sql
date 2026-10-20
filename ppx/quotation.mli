open! Base

(** Decode a PG'OCaml quotation without expanding it. Flags are validated here
    so collection and expansion accept the same inputs. *)
val payload
  :  loc:Ppxlib.Location.t
  -> Ppxlib.payload
  -> Ppxlib.expression * string list * string * Ppxlib.Location.t

(** Reject unsupported legacy environment configuration with a located
    PPX error. This check performs no database access. *)
val check_environment : loc:Ppxlib.Location.t -> unit
