open! Base
open Typed_sql

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let name_column = Column.v_exn table "name" Db_type.text
  let name reference = Expr.column reference name_column
end

let compile value =
  Query.from Item.table ~select:(fun item -> Projection.expr (Item.name item))
  |> Query.where (fun item -> Expr.eq_value (Item.name item) value)
  |> Compiler.compile ~dialect:Dialect.Sqlite
;;

let parameter_count_matches =
  QCheck.Test.make
    ~name:"bind node count equals extracted parameter count"
    ~count:500
    QCheck.string
    (fun value ->
       let value = "__bound_value_" ^ value ^ "__" in
       match compile value with
       | Error _ -> false
       | Ok compiled ->
         let bind_count =
           Typed_sql.Template.parts (Compiled_query.template compiled)
           |> List.count ~f:(function
             | Template.Param _ -> true
             | Template.Text _ -> false)
         in
         Int.equal bind_count (List.length (Compiled_query.parameters compiled)))
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
  QCheck_runner.run_tests_main [ parameter_count_matches; values_never_appear_in_sql ]
;;
