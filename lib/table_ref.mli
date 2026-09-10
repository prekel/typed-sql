open! Base

(** An occurrence of a table in one query. Values are created by [Query.from];
    an escaped reference from another query is rejected by the compiler. *)
type 'row t

val create : 'row Table.t -> 'row t
val table : 'row t -> 'row Table.t
val source_id : 'row t -> int
