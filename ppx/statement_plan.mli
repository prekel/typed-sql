open! Base

(** One returned column in SQL order, including its transport codec and nullability. *)
type field =
  { name : string (** Result-column name in the SQL output layout. *)
  ; codec : Codec.t (** Resolved transport conversion for the non-null field value. *)
  ; nullable : bool (** Whether decoding wraps the field value in an option. *)
  }

(** A substitution paired with the conversion required by its resolved SQL context. *)
type parameter =
  { value : Query_bind.parameter
    (** The original source substitution, without evaluating its expression. *)
  ; codec : Codec.t (** Resolved PG'OCaml transport conversion for this substitution. *)
  }

(** Rows always contains at least one field. Command preserves the PG'OCaml
    unit-result contract for DML without RETURNING. *)
type result =
  | Command (** No returned fields; preserve the PG'OCaml unit-result contract. *)
  | Rows of field list (** Nonempty result layout in server output order. *)

(** Executable SQL and its ordered conversion plans. No connection or
    runtime OCaml parameter values are retained. *)
type t =
  { sql : string
    (** SQL rewritten to positional placeholders; OCaml values stay separate. *)
  ; result : result (** Command or row-result decoding contract. *)
  ; parameters : parameter list (** Bind occurrences in SQL/source order. *)
  }

(** Returned fields, or an empty list for a command. *)
val fields : t -> field list
