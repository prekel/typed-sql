open! Base
open Typed_sql
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let name_column = Column.v_exn table "name" Db_type.text
  let name reference = Expr.column reference name_column
end

let compile value =
  Query.(
    from Item.table
    |> where (fun item -> Item.name item =$ value)
    |> select (fun item -> Projection.expr (Item.name item)))
  |> Compiler.compile ~dialect:Dialect.Sqlite
;;

let placeholder_count_matches =
  QCheck.Test.make
    ~name:"compiled SQL contains one placeholder for one bound value"
    ~count:500
    QCheck.string
    (fun value ->
       let value = "__bound_value_" ^ value ^ "__" in
       match compile value with
       | Error _ -> false
       | Ok compiled -> String.count (Compiled_query.sql compiled) ~f:(Char.equal '?') = 1)
;;

let values_never_appear_in_sql =
  QCheck.Test.make
    ~name:"bound values are never inlined"
    ~count:500
    QCheck.string
    (fun value ->
       let value = "__bound_value_" ^ value ^ "__" in
       match compile value with
       | Error _ -> false
       | Ok compiled ->
         not (String.is_substring (Compiled_query.sql compiled) ~substring:value))
;;

let () =
  QCheck_runner.run_tests_main [ placeholder_count_matches; values_never_appear_in_sql ]
;;
