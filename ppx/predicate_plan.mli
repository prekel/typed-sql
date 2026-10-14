open! Base

type parameter =
  { value : Sql.parameter
  ; codec : Codec.t
  }

(** Check predicates and infer each substitution's exact conversion context. *)
val create
  :  resolve:(Sql.reference -> (Typed_sql_schema.Schema_ir.column, Sql.error) Result.t)
  -> Sql.predicate option
  -> (parameter list, Sql.error) Result.t
