open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let name = Column.v_exn table "name" Db_type.text
end

let command = Update.(table Item.table |> default Item.name |> all_rows |> command)
let _ = Compiler.compile_command ~dialect:Dialect.sqlite command
