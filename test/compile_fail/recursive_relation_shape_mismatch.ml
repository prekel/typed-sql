open! Base
open Typed_sql

let anchor = Query.select_one_relation (Expr.constant Db_type.int 1)

let _invalid =
  Cte.recursive_relation ~union:`Union_all ~anchor ~step:(fun numbers ->
    Query.(
      from_cte_relation numbers
      |> select_relation (fun value -> Derived_table.Fields.pair value value)))
;;
