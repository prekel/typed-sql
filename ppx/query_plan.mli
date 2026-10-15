open! Base

type field =
  { name : string
  ; codec : Codec.t
  ; nullable : bool
  }

type parameter =
  { value : Sql_query.parameter
  ; codec : Codec.t
  }

type t =
  { fields : field list
  ; parameters : parameter list
  }

(** Infer exact supported PostgreSQL codecs and PG'OCaml column-origin
    nullability without a connection. Parameters are ordered by source offset. *)
val create
  :  Typed_sql_schema.Schema_ir.t
  -> Sql_query.statement
  -> (t, Sql_query.error) Result.t
