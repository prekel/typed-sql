open Typed_sql
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
end

let query =
  Query.(
    from Person.table
    |> Postgresql.Query.having (fun person ->
      Expr.count (Expr.column person Person.id_column) =$ "wrong")
    |> select (fun _ -> Projection.expr Expr.count_all))
;;
