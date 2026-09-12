open Typed_sql
open Infix

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
        (Expr.case
           [ ( Expr.column person Person.id_column =$ 1L
             , Expr.column person Person.name_column )
           ]
           ~else_:(Expr.column person Person.id_column))))
;;
