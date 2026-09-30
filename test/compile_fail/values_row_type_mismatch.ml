open! Base
open Typed_sql

module Selected = struct
  type row

  let table : row Table.t = Table.v_exn "selected"
  let value = Column.v_exn table "value" Db_type.int64
end

let _values =
  Values.create
    ~table:Selected.table
    ~columns:(fun selected -> Projection.expr (Expr.column selected Selected.value))
    ~first:(Values.Row.expr (Expr.constant Db_type.int64 1L))
    ~rest:[ Values.Row.expr (Expr.constant Db_type.text "two") ]
;;
