open! Base

(** A table occurrence made nullable by an outer join. *)
type 'row t

module Private : sig
  val of_table_ref : 'row Table_ref.t -> 'row t
  val table : 'row t -> 'row Table.t
  val source_id : 'row t -> int
end
