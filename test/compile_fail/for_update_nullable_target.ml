open! Base
open Typed_sql
open Infix

module Parent = struct
  type row

  let table : row Table.t = Table.v_exn "parent"
  let id = Column.v_exn table "id" Db_type.int
end

module Child = struct
  type row

  let table : row Table.t = Table.v_exn "child"
  let parent_id = Column.v_exn table "parent_id" Db_type.int
end

let _ =
  Query.(
    from Parent.table
    |> left_join Child.table ~on:(fun parent child ->
      Expr.column parent Parent.id =. Expr.column child Child.parent_id)
    |> Postgresql.Query.for_update ~of_:(fun (_, child) ->
      [ Postgresql.Query.target child ])
    |> select (fun (parent, _) -> Projection.expr (Expr.column parent Parent.id)))
;;
