open! Base

type ('row, 'base, 'value) t =
  { table : 'row Table.t
  ; name : Identifier.t
  ; base_db_type : 'base Db_type.t
  ; db_type : 'value Db_type.t
  }

let v table name db_type = { table; name; base_db_type = db_type; db_type }
let v_exn table name db_type = v table (Identifier.of_string_exn name) db_type

let nullable_v table name base_db_type =
  { table; name; base_db_type; db_type = Db_type.option base_db_type }
;;

let nullable_v_exn table name db_type =
  nullable_v table (Identifier.of_string_exn name) db_type
;;

let table column = column.table
let name column = column.name
let base_db_type column = column.base_db_type
let db_type column = column.db_type
