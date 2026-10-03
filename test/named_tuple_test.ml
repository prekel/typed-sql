open! Base
open Typed_sql
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let id item = Expr.column item id_column
end

type input = minimum:int64 * maximum:int64

let annotated_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let%map minimum =
      params.column Item.id_column ~get:(fun ((~minimum, ..) : input) -> minimum)
    and maximum =
      params.column Item.id_column ~get:(fun ((~maximum, ..) : input) -> maximum)
    in
    params.query_many
      Query.(
        from Item.table
        |> where (fun item -> Item.id item >=. minimum &&. (Item.id item <=. maximum))
        |> select (fun item -> Projection.expr (Item.id item))))
;;

let inferred_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    let open Statement.Parameters.Let_syntax in
    let%map minimum =
      params.column Item.id_column ~get:(fun (~minimum, ~maximum:_) -> minimum)
    and maximum =
      params.column Item.id_column ~get:(fun (~minimum:_, ~maximum) -> maximum)
    in
    params.query_many
      Query.(
        from Item.table
        |> where (fun item -> Item.id item >=. minimum &&. (Item.id item <=. maximum))
        |> select (fun item -> Projection.expr (Item.id item))))
;;

let named_tuple_input = ~minimum:1L, ~maximum:10L

let%test_unit "annotated and inferred named tuple inputs compile equivalently" =
  let sql statement =
    Statement.sql_exn ~dialect:Postgresql ~input:named_tuple_input statement
  in
  assert (String.equal (sql annotated_statement) (sql inferred_statement))
;;
