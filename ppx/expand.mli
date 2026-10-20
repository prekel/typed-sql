open! Base

(** Register [pgsql] and [pgsql.object] expression extensions. Expansion
    uses the single embedded schema or query-cache provider; it never opens
    a database connection or reads a snapshot file. *)
val register : unit -> unit
