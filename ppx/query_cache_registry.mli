open! Base

(** Register embedded metadata during driver initialization. Exactly one cache
    must be registered; duplicate registrations are rejected at the quotation. *)
val register : Query_cache.t -> unit

(** Resolve the sole embedded cache, raising a located diagnostic if absent or
    ambiguous. No file or database lookup is performed. *)
val current : loc:Ppxlib.Location.t -> Query_cache.t
