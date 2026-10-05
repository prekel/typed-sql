(** This file tests the syntax available without ppx_let. Use let+/and+ instead
    of let%map here. Other OCaml files use qualified ppx_let syntax. *)

open! Base
open Typed_sql
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int
  let name_column = Column.v_exn table "name" Db_type.text
  let age_column = Column.v_exn table "age" Db_type.int
  let id item = Expr.column item id_column
  let name item = Expr.column item name_column
  let age item = Expr.column item age_column
end

let projection_sql projection =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(from Item.table |> select (fun _ -> projection))
  |> Statement.sql_exn ~dialect:Postgresql
;;

let%test "Projection.Let_syntax preserves field order" =
  let projection =
    let open Projection.Let_syntax in
    let+ first = Projection.expr (Expr.constant Db_type.int 3)
    and+ second = Projection.expr (Expr.constant Db_type.int 5) in
    first, second
  in
  String.is_substring (projection_sql projection) ~substring:"$1,\n  $2"
;;

let%test "nested Projection.Let_syntax preserves field order" =
  let projection =
    let open Projection.Let_syntax.Let_syntax in
    let+ first = Projection.expr (Expr.constant Db_type.int 3)
    and+ second = Projection.expr (Expr.constant Db_type.int 5) in
    first, second
  in
  String.is_substring (projection_sql projection) ~substring:"$1,\n  $2"
;;

let aggregate_sql project =
  let query = Query.Aggregate.(from Item.table) |> Query.aggregate_one project in
  Statement.query_many ~dialect:Dialect.portable query
  |> Statement.sql_exn ~dialect:Sqlite
;;

let%test "Aggregate_projection.Let_syntax combines aggregate fields" =
  let sql =
    aggregate_sql (fun item ->
      let open Aggregate_projection.Let_syntax in
      let+ total = Aggregate_projection.sum_int (Item.age item)
      and+ count = Aggregate_projection.count_all in
      total, count)
  in
  String.is_substring sql ~substring:"SUM("
  && String.is_substring sql ~substring:"COUNT(*)"
;;

let%test "nested Aggregate_projection.Let_syntax combines aggregate fields" =
  let sql =
    aggregate_sql (fun item ->
      let open Aggregate_projection.Let_syntax.Let_syntax in
      let+ total = Aggregate_projection.sum_int (Item.age item)
      and+ count = Aggregate_projection.count_all in
      total, count)
  in
  String.is_substring sql ~substring:"SUM("
  && String.is_substring sql ~substring:"COUNT(*)"
;;

let parameter_sql use_nested =
  let statement =
    if use_nested then
      Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
        let open Parameters.Let_syntax.Let_syntax in
        let+ expected_name = params.expr Db_type.text ~get:fst
        and+ minimum_age = params.expr Db_type.int ~get:snd in
        params.query_many
          Query.(
            from Item.table
            |> where (fun item ->
              Item.name item =. expected_name &&. (Item.age item >=. minimum_age))
            |> select (fun item -> Projection.expr (Item.id item))))
    else
      Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
        let open Parameters.Let_syntax in
        let+ expected_name = params.expr Db_type.text ~get:fst
        and+ minimum_age = params.expr Db_type.int ~get:snd in
        params.query_many
          Query.(
            from Item.table
            |> where (fun item ->
              Item.name item =. expected_name &&. (Item.age item >=. minimum_age))
            |> select (fun item -> Projection.expr (Item.id item))))
  in
  Statement.sql_exn ~dialect:Postgresql ~input:("Ada", 18) statement
;;

let%test "Parameters.Let_syntax assigns bind slots in declaration order" =
  let sql = parameter_sql false in
  String.is_substring sql ~substring:"= $1" && String.is_substring sql ~substring:">= $2"
;;

let%test "nested Parameters.Let_syntax assigns bind slots in declaration order" =
  let sql = parameter_sql true in
  String.is_substring sql ~substring:"= $1" && String.is_substring sql ~substring:">= $2"
;;
