open! Base
open Typed_sql

module Selected = struct
  type row

  let table : row Table.t = Table.v_exn "selected"
  let id = Column.v_exn table "id" Db_type.int64
  let label = Column.v_exn table "label" Db_type.text
end

let _values =
  Values.create
    ~table:Selected.table
    ~columns:(fun selected ->
      Projection.pair
        (Expr.column selected Selected.id)
        (Expr.column selected Selected.label))
    ~first:(Values.Row.expr (Expr.constant Db_type.int64 1L))
    ~rest:
      [ Values.Row.pair
          (Expr.constant Db_type.int64 2L)
          (Expr.constant Db_type.text "two")
      ]
;;
