open! Base

(** One inferred result column. Nullable columns use an outer option codec. *)
type field =
  { name : string (** Result-column name in the SQL output layout. *)
  ; codec : Codec.t (** Resolved transport conversion for the non-null field value. *)
  ; nullable : bool (** Whether decoding wraps the field value in an option. *)
  }

(** One source substitution and its inferred PostgreSQL transport codec. *)
type parameter =
  { value : Sql_query.parameter
    (** The original source substitution, without evaluating its expression. *)
  ; codec : Codec.t (** Resolved PG'OCaml transport conversion for this substitution. *)
  }

(** An offline SELECT result layout and source-ordered parameter conversions. *)
type t =
  { fields : field list (** Returned columns in decoder order. *)
  ; parameters : parameter list (** Bind occurrences in SQL/source order. *)
  }

(** Infer exact supported PostgreSQL codecs and PG'OCaml column-origin
    nullability without a connection. Parameters are ordered by source offset. *)
val create
  :  Typed_sql_schema.Schema_ir.t
  -> Sql_query.statement
  -> (t, Sql_query.error) Result.t
