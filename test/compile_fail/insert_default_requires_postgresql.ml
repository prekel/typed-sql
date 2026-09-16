open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id = Column.v_exn table "id" Db_type.int
end

let command = Insert.(into Item.table |> default Item.id |> command)
let _ = Compiler.compile_command ~dialect:Dialect.sqlite command
