open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
end

let query =
  Query.(
    from Person.table
    |> select (fun person ->
      Projection.expr
        (Expr.Int64.add
           (Expr.column person Person.id_column)
           (Expr.column person Person.name_column))))
;;
