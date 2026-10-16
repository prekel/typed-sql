open! Base
open Typed_sql

let legacy dbh (id : int32) : int32 option list = [%pgsql dbh "SELECT $id::int4"]

let typed : (int, < id : int ; name : string > list, [ `Postgresql ]) Statement.t =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id = params.expr Db_type.int ~get:Fn.id in
    params.query_many
      [%pgsql.query.object "SELECT id, name FROM typed_sql_query_items WHERE id = $id"])
;;
