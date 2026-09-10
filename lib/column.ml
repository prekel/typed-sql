open! Base

type ('row, 'a) t =
  { table : 'row Table.t
  ; name : Identifier.t
  ; db_type : 'a Db_type.t
  }

let v table name db_type = { table; name; db_type }
let v_exn table name db_type = v table (Identifier.of_string_exn name) db_type
let table column = column.table
let name column = column.name
let db_type column = column.db_type
