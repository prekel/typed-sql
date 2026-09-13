open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let name_column = Column.v_exn table "name" Db_type.text
  let name reference = Expr.column reference name_column
end

let names = Query.(from Person.table |> limit 1 |> select_scalar Person.name)
let value : string Expr.t = Expr.scalar_subquery names
