open Typed_sql
open Infix

module Event = struct
  type row

  let table : row Table.t = Table.v_exn "events"
  let occurred_on_column = Column.v_exn table "occurred_on" Db_type.date
end

let query =
  Query.(
    from Event.table
    |> where (fun event ->
      Expr.column event Event.occurred_on_column =. Expr.current_timestamp)
    |> select (fun event -> Projection.expr (Expr.column event Event.occurred_on_column)))
;;
