open! Base

(** A column tied to a table's phantom row type. ['base] is the non-null SQL
    value type and ['value] is the value read from a regular table reference. *)
type ('row, 'base, 'value) t

val v : 'row Table.t -> Identifier.t -> 'a Db_type.t -> ('row, 'a, 'a) t
val v_exn : 'row Table.t -> string -> 'a Db_type.t -> ('row, 'a, 'a) t
val nullable_v : 'row Table.t -> Identifier.t -> 'a Db_type.t -> ('row, 'a, 'a option) t
val nullable_v_exn : 'row Table.t -> string -> 'a Db_type.t -> ('row, 'a, 'a option) t
val table : ('row, 'base, 'value) t -> 'row Table.t
val name : ('row, 'base, 'value) t -> Identifier.t
val base_db_type : ('row, 'base, 'value) t -> 'base Db_type.t
val db_type : ('row, 'base, 'value) t -> 'value Db_type.t
