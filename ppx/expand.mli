open! Base

(** Register [pgsql] and [pgsql.object] extensions. Expansion scans substitutions
    and uses the sole embedded query cache. No file or database is read during
    expansion. *)
val register : unit -> unit
