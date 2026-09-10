open! Base

type 'row t =
  { table : 'row Table.t
  ; source_id : int
  }

let next_source = Atomic.make 0

let create table =
  let source_id = Atomic.fetch_and_add next_source 1 in
  { table; source_id }
;;

let table reference = reference.table
let source_id reference = reference.source_id
