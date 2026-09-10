open! Base
open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
end

module Site = struct
  type row

  let table : row Table.t = Table.v_exn "sites"
  let id_column = Column.v_exn table "id" Db_type.int64
end

let _ =
  Query.from Person.table ~select:(fun person ->
    Projection.expr (Expr.column person Site.id_column))
;;
