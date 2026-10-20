open! Base

(** The driver's single offline metadata source: schema inference or
    exact query descriptions. Resolution never falls back to a live database. *)
type source =
  | Schema of Typed_sql_schema.Schema_ir.t
  (** Infer supported SQL using an embedded schema snapshot. *)
  | Queries of Query_cache.t
  (** Resolve exact SQL through embedded Prepare/Describe metadata. *)

(** Register embedded schema metadata during PPX driver initialization.
    Multiple registrations are rejected when a quotation resolves its source. *)
val register : Typed_sql_schema.Schema_ir.t -> unit

(** Register embedded Prepare/Describe metadata during driver initialization.
    It shares the single-provider requirement with [register]. *)
val register_queries : Query_cache.t -> unit

(** Resolve the single metadata provider. Errors are attached to the quotation
    when no provider, or several providers, were linked into the driver. *)
val source : loc:Ppxlib.Location.t -> source

(** Compatibility accessor for schema-based consumers. Raises a located error
    when the registered source is a query cache. *)
val current : loc:Ppxlib.Location.t -> Typed_sql_schema.Schema_ir.t
