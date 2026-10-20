open! Base

(** A scanned quotation together with its source location for located diagnostics. *)
type t =
  { query : Query_bind.t
    (** Scanned literal with rewritten SQL and source substitutions. *)
  ; loc : Ppxlib.Location.t
    (** Original quotation location for located PPX diagnostics. *)
  }

(** Collect literal quotations in a source AST. Quotations introduced by other
    preprocessors are outside this collector's input. Parse errors retain their
    source locations. *)
val collect_exn : Ppxlib.structure -> t list
