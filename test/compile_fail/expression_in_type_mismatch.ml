open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
end

let query =
  Query.(
    from Person.table
    |> where (fun person -> Expr.in_ (Expr.column person Person.id_column) [ "wrong" ])
    |> select (fun person -> Projection.expr (Expr.column person Person.id_column)))
;;
