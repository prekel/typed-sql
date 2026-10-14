open! Base

(** Register the two PG'OCaml expression extensions. Snapshot reads happen
    only for these extensions; compilation never opens a database connection. *)
val register : unit -> unit
