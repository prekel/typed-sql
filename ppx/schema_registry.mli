open! Base

type source =
  | Schema of Typed_sql_schema.Schema_ir.t
  | Queries of Query_cache.t

val register : Typed_sql_schema.Schema_ir.t -> unit
val register_queries : Query_cache.t -> unit

(** Resolve the single metadata provider. Errors are attached to the quotation
    when no provider, or several providers, were linked into the driver. *)
val source : loc:Ppxlib.Location.t -> source

(** Compatibility accessor for schema-based consumers. Raises a located error
    when the registered source is a query cache. *)
val current : loc:Ppxlib.Location.t -> Typed_sql_schema.Schema_ir.t
