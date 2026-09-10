open! Base

(** A column tied to a table's phantom row type and an OCaml value type. *)
type ('row, 'a) t

val v : 'row Table.t -> Identifier.t -> 'a Db_type.t -> ('row, 'a) t
val v_exn : 'row Table.t -> string -> 'a Db_type.t -> ('row, 'a) t
val table : ('row, 'a) t -> 'row Table.t
val name : ('row, 'a) t -> Identifier.t
val db_type : ('row, 'a) t -> 'a Db_type.t
