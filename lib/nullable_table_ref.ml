open! Base

type 'row t = 'row Table_ref.t

let of_table_ref reference = reference
let table = Table_ref.table
let source_id = Table_ref.source_id
