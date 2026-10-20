open! Base

(** One OCaml substitution paired with the codec inferred from its SQL context. *)
type parameter =
  { value : Sql.parameter
    (** The original source substitution, without evaluating its expression. *)
  ; codec : Codec.t (** Resolved PG'OCaml transport conversion for this substitution. *)
  }

(** Check predicates and infer each substitution's exact conversion context. *)
val create
  :  resolve:(Sql.reference -> (Typed_sql_schema.Schema_ir.column, Sql.error) Result.t)
  -> Sql.predicate option
  -> (parameter list, Sql.error) Result.t
