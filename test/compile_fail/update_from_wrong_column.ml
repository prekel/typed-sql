open! Base
open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let name = Column.v_exn table "name" Db_type.text
end

module Department = struct
  type row

  let table : row Table.t = Table.v_exn "departments"
end

let _ =
  Update.(
    table Person.table
    |> from Department.table ~f:(fun _ department update ->
      update |> set_expr Person.name (Expr.column department Person.name) |> all_rows)
    |> command)
;;
