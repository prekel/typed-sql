open! Base
open Typed_sql

let find =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.expr Db_type.int ~get:Fn.id in
    params.query_many
      [%pgsql.query.object "SELECT id, name FROM typed_sql_query_items WHERE id = $id"])
;;

let insert =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.expr Db_type.int ~get:fst
    and name = params.expr Db_type.text ~get:snd in
    params.query_many
      [%pgsql.query
        "INSERT INTO typed_sql_query_items (id, name) VALUES ($id, $name) RETURNING id, name"])
;;

let update =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.expr Db_type.int ~get:fst
    and name = params.expr Db_type.text ~get:snd in
    params.command
      [%pgsql.command "UPDATE typed_sql_query_items SET name = $name WHERE id = $id"])
;;

let delete =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.expr Db_type.int ~get:Fn.id in
    params.command [%pgsql.command "DELETE FROM typed_sql_query_items WHERE id = $id"])
;;

let nullable =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters name = params.expr (Db_type.option Db_type.text) ~get:Fn.id in
    params.query_many [%pgsql.query "SELECT $?name::text AS name; -- trailing comment"])
;;

let constant () = [%pgsql.query "SELECT 1::int4 AS id"]

module Row = struct
  type t

  let table : t Table.t = Table.v_exn "typed_sql_query_items"
  let id_column = Column.v_exn table "id" (Db_type.option Db_type.int)
  let projection row = Projection.expr (Expr.column row id_column)
end

let union =
  Statement.query_many
    ~dialect:Dialect.postgresql
    (Query.union_all (constant ()) Query.(from Row.table |> select Row.projection))
;;

let relation () =
  Derived_table.create ~table:Row.table ~columns:Row.projection (constant ())
;;

let derived =
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(from_derived (relation ()) |> select Row.projection)
;;

let cte =
  Statement.query_many
    ~dialect:Dialect.postgresql
    (Cte.with_result
       (Cte.select (relation ()))
       ~f:(fun cte -> Query.(from_cte cte |> select Row.projection)))
;;

let types =
  Statement.query_many
    ~dialect:Dialect.postgresql
    [%pgsql.query
      "SELECT '1.25'::numeric AS amount, ARRAY[1, NULL, 3]::int4[] AS numbers, 'ready'::typed_sql_query_mood AS mood"]
;;

let modifying_cte =
  Statement.query_many
    ~dialect:Dialect.postgresql
    [%pgsql.query
      "WITH inserted AS (INSERT INTO typed_sql_query_items VALUES (7, 'CTE') RETURNING id) SELECT id FROM inserted"]
;;

let enum_input =
  let mood_type =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "typed_sql_query_mood")
      Db_type.text
  in
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters mood = params.expr mood_type ~get:Fn.id in
    params.query_many [%pgsql.query "SELECT $mood::typed_sql_query_mood"])
;;

let domain_input =
  let tag_type =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "typed_sql_query_tag")
      Db_type.int
  in
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters tag = params.expr tag_type ~get:Fn.id in
    params.query_many [%pgsql.query "SELECT $tag::typed_sql_query_tag"])
;;

let nested =
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(from Row.table |> select (fun _ -> multiset (constant ())))
;;

module Item = struct
  type t

  let table : t Table.t = Table.v_exn "typed_sql_query_items"
  let id = Column.v_exn table "id" Db_type.int
  let name = Column.v_exn table "name" Db_type.text
end

let dsl_insert =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.column Item.id ~get:fst
    and name = params.column Item.name ~get:snd in
    params.command
      Insert.(
        into Item.table |> set_expr Item.id id |> set_expr Item.name name |> command))
;;

let nullable_people =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.expr Db_type.int ~get:Fn.id in
    params.query_many
      [%pgsql.query.object
        "nullable-results" "SELECT id, name FROM typed_sql_query_items WHERE id = $id"])
;;

let array_input =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters numbers =
      params.expr (Db_type.Postgresql.array Db_type.int) ~get:Fn.id
    in
    params.query_many [%pgsql.query "SELECT $numbers::int4[] AS numbers"])
;;

let find_direct =
  [%pgsql.statement.object
    fun id -> "SELECT id, name FROM typed_sql_query_items WHERE id = $id"]
;;

type insert_input =
  { id : int
  ; name : string
  }

let insert_direct =
  [%pgsql.statement
    fun { id; name } ->
      "INSERT INTO typed_sql_query_items (id, name) VALUES ($id, $name) RETURNING id, name"]
;;

let delete_direct =
  [%pgsql.statement fun id -> "DELETE FROM typed_sql_query_items WHERE id = $id"]
;;

let nullable_direct =
  [%pgsql.statement fun name -> "SELECT $?name::text AS name; -- trailing comment"]
;;

let constant_statement = [%pgsql.statement "SELECT 1::int4 AS id"]

let nullable_people_direct =
  [%pgsql.statement.object
    fun id ->
      "nullable-results" "SELECT id, name FROM typed_sql_query_items WHERE id = $id"]
;;

let expression_direct =
  [%pgsql.statement.object
    fun next_id -> "SELECT id, name FROM typed_sql_query_items WHERE id = ${next_id ()}"]
;;

let tuple_direct =
  [%pgsql.statement
    fun (id, name) ->
      "INSERT INTO typed_sql_query_items (id, name) VALUES ($id, $name) RETURNING id, name"]
;;

let record_expression_direct =
  [%pgsql.statement.object
    fun (input : insert_input) ->
      "SELECT id, name FROM typed_sql_query_items WHERE id = ${input.id}"]
;;

let json_rows () = [%pgsql.query "SELECT value FROM typed_sql_query_json ORDER BY id"]

let nested_json =
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(from Row.table |> select (fun _ -> multiset (json_rows ())))
;;

module Json_row = struct
  type t

  let table : t Table.t = Table.v_exn "typed_sql_query_json"
  let id = Column.v_exn table "id" Db_type.int
  let value = Column.v_exn table "value" (Db_type.option Db_type.Postgresql.jsonb)
end

let aggregated_json =
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(
      from Json_row.table
      |> select (fun row ->
        Projection.multiset_agg
          ~order_by:[ Aggregate_order.asc (Expr.column row Json_row.id) ]
          (Projection.expr (Expr.column row Json_row.value))))
;;

let json_text_rows =
  [%pgsql.query "SELECT value::json AS value FROM typed_sql_query_json ORDER BY id"]
;;

let nested_json_text =
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(from Row.table |> select (fun _ -> multiset json_text_rows))
;;

let nested_locked =
  let locked =
    [%pgsql.query
      "SELECT id FROM typed_sql_query_items WHERE EXISTS (SELECT 1 FROM typed_sql_query_items FOR UPDATE)"]
  in
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(from Row.table |> select (fun _ -> multiset locked))
;;

let nested_locked_cte =
  let locked =
    [%pgsql.query
      "WITH locked AS (SELECT id FROM typed_sql_query_items FOR UPDATE) SELECT id FROM locked"]
  in
  Statement.query_many
    ~dialect:Dialect.postgresql
    Query.(from Row.table |> select (fun _ -> multiset locked))
;;
