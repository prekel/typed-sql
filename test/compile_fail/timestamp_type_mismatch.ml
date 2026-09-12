open Typed_sql
open Infix

module Event = struct
  type row

  let table : row Table.t = Table.v_exn "events"
  let occurred_at_column = Column.v_exn table "occurred_at" Db_type.timestamp
end

let query =
  Query.(
    from Event.table
    |> where (fun event -> Expr.column event Event.occurred_at_column =$ "wrong")
    |> select (fun event -> Projection.expr (Expr.column event Event.occurred_at_column)))
;;
