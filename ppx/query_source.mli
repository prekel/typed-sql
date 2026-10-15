open! Base

type t =
  { query : Query_bind.t
  ; loc : Ppxlib.Location.t
  }

(** Collect literal quotations in a source AST. Quotations introduced by other
    preprocessors are outside this collector's input. Parse errors retain their
    source locations. *)
val collect_exn : Ppxlib.structure -> t list
