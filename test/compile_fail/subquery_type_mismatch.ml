open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
end

let ids =
  Query.(
    from Person.table |> select_scalar (fun person -> Expr.column person Person.id_column))
;;

let query =
  Query.(
    from Person.table
    |> where (fun person -> in_subquery (Expr.column person Person.name_column) ids)
    |> select (fun person -> Projection.expr (Expr.column person Person.id_column)))
;;
