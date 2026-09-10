open! Base

type 'row t = 'row Table_ref.t

module Private = struct
  let of_table_ref reference = reference
  let table = Table_ref.table
  let source_id = Table_ref.source_id
end
