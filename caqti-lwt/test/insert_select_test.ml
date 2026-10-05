open! Base
open Typed_sql
open Infix
module T = Caqti.Template
module Adapter = Typed_sql_caqti_lwt

let ( let* ) = Lwt.bind

let direct sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit)
    (fun _ -> T.Query.parse sql)
;;

let caqti_or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

let adapter_or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Adapter.error_to_string error)
;;

module Source = struct
  type row

  let table : row Table.t = Table.v_exn "insert_select_source"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let year_column = Column.v_exn table "year" Db_type.int64
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
  let year row = Expr.column row year_column
end

module Target = struct
  type row

  let table : row Table.t = Table.v_exn "insert_select_target"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
  let projection row = Projection.pair (id row) (name row)
end

module Singleton = struct
  type row

  let table : row Table.t = Table.v_exn "insert_select_singleton"
  let id_column = Column.v_exn table "id" Db_type.int64
  let id row = Expr.column row id_column
end

let columns = Insert.Columns.(column Target.id_column |> add Target.name_column)

let all_source =
  Query.(
    from Source.table
    |> select (fun row -> Projection.pair (Source.id row) (Source.name row)))
;;

let filtered_statement =
  Statement.with_parameters ~dialect:Dialect.portable (fun ~params ->
    Parameters.map (params.expr Db_type.int64 ~get:Fn.id) ~f:(fun cutoff ->
      let source =
        Query.(
          from Source.table
          |> where (fun row -> Source.year row <. cutoff)
          |> select (fun row -> Projection.pair (Source.id row) (Source.name row)))
      in
      params.query_many
        Insert.(
          into Target.table
          |> from_select columns source
          |> on_conflict_do_nothing
          |> returning (fun row -> Projection.expr (Target.id row)))))
;;

let unfiltered_statement =
  Statement.query_many
    ~dialect:Dialect.portable
    Insert.(
      into Target.table
      |> from_select columns all_source
      |> on_conflict_do_nothing
      |> returning (fun row -> Projection.expr (Target.id row)))
;;

let compound_statement =
  Statement.query_many
    ~dialect:Dialect.portable
    (let older =
       Query.(
         from Source.table
         |> where (fun row -> Source.year row <$ 1900L)
         |> select (fun row -> Projection.pair (Source.id row) (Source.name row)))
     in
     let newer =
       Query.(
         from Source.table
         |> where (fun row -> Source.year row >$ 2000L)
         |> select (fun row -> Projection.pair (Source.id row) (Source.name row)))
     in
     Insert.(
       into Target.table
       |> from_select columns (Query.union_all older newer)
       |> on_conflict_do_nothing
       |> returning (fun row -> Projection.expr (Target.id row))))
;;

let cte_statement =
  let relation =
    Derived_table.create ~table:Target.table ~columns:Target.projection all_source
  in
  let source =
    Cte.with_result (Cte.select relation) ~f:(fun selected ->
      Query.(from_cte selected |> select Target.projection))
  in
  Statement.query_many
    ~dialect:Dialect.portable
    Insert.(
      into Target.table
      |> from_select columns source
      |> returning (fun row -> Projection.expr (Target.id row)))
;;

let update_statement =
  Statement.query_many
    ~dialect:Dialect.portable
    Insert.(
      into Target.table
      |> from_select columns all_source
      |> on_conflict (Conflict_target.column Target.id_column)
      |> do_update (fun ~existing:_ ~excluded ->
        Conflict_update.(empty |> set_expr Target.name_column (Target.name excluded)))
      |> returning (fun row -> Projection.expr (Target.id row)))
;;

let singleton_statement =
  Statement.query_many
    ~dialect:Dialect.portable
    Insert.(
      into Singleton.table
      |> from_select
           (Columns.column Singleton.id_column)
           (Query.select_one (Expr.constant Db_type.int64 99L))
      |> on_conflict_do_nothing
      |> returning (fun row -> Projection.expr (Singleton.id row)))
;;

let read_statement =
  Statement.query_many
    ~dialect:Dialect.portable
    Query.(from Target.table |> order_by Target.id `Asc |> select Target.projection)
;;

let exec conn sql =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Connection.exec (direct sql) () |> caqti_or_fail
;;

let fetch conn statement input =
  let* result = Adapter.run ~conn statement input in
  adapter_or_fail result
;;

let check_ids ~name expected actual =
  let actual = List.sort actual ~compare:Int64.compare in
  if not (List.equal Int64.equal expected actual) then
    failwith (name ^ " returned unexpected IDs")
;;

let check_target ~name conn expected =
  let* actual = fetch conn read_statement () in
  let equal (left_id, left_name) (right_id, right_name) =
    Int64.equal left_id right_id && String.equal left_name right_name
  in
  if not (List.equal equal expected actual) then
    failwith (name ^ " left unexpected target rows");
  Lwt.return_unit
;;

let run conn =
  let* () =
    exec
      conn
      "CREATE TABLE insert_select_source (id BIGINT NOT NULL, name TEXT NOT NULL, year BIGINT NOT NULL)"
  in
  let* () =
    exec
      conn
      "CREATE TABLE insert_select_target (id BIGINT PRIMARY KEY, name TEXT NOT NULL)"
  in
  let* () = exec conn "CREATE TABLE insert_select_singleton (id BIGINT PRIMARY KEY)" in
  let* () =
    exec
      conn
      "INSERT INTO insert_select_source (id, name, year) VALUES (1, 'old', 1800), (2, 'new', 2020), (3, 'older', 1850)"
  in
  let* () = exec conn "INSERT INTO insert_select_target VALUES (1, 'existing')" in
  let* inserted = fetch conn filtered_statement 1900L in
  check_ids ~name:"filtered INSERT SELECT with conflict" [ 3L ] inserted;
  let* () =
    check_target
      ~name:"filtered INSERT SELECT with conflict"
      conn
      [ 1L, "existing"; 3L, "older" ]
  in
  let* inserted = fetch conn unfiltered_statement () in
  check_ids ~name:"unfiltered INSERT SELECT" [ 2L ] inserted;
  let* () =
    check_target
      ~name:"unfiltered INSERT SELECT"
      conn
      [ 1L, "existing"; 2L, "new"; 3L, "older" ]
  in
  let* inserted = fetch conn filtered_statement 0L in
  check_ids ~name:"empty SELECT source" [] inserted;
  let* () = exec conn "DELETE FROM insert_select_target" in
  let* inserted = fetch conn compound_statement () in
  check_ids ~name:"compound SELECT source" [ 1L; 2L; 3L ] inserted;
  let* () =
    check_target ~name:"compound SELECT source" conn [ 1L, "old"; 2L, "new"; 3L, "older" ]
  in
  let* () = exec conn "DELETE FROM insert_select_target" in
  let* inserted = fetch conn cte_statement () in
  check_ids ~name:"CTE SELECT source" [ 1L; 2L; 3L ] inserted;
  let* () =
    check_target ~name:"CTE SELECT source" conn [ 1L, "old"; 2L, "new"; 3L, "older" ]
  in
  let* () = exec conn "UPDATE insert_select_target SET name = 'stale' WHERE id = 1" in
  let* updated = fetch conn update_statement () in
  check_ids ~name:"INSERT SELECT DO UPDATE" [ 1L; 2L; 3L ] updated;
  let* () =
    check_target
      ~name:"INSERT SELECT DO UPDATE"
      conn
      [ 1L, "old"; 2L, "new"; 3L, "older" ]
  in
  let* inserted = fetch conn singleton_statement () in
  check_ids ~name:"source-free INSERT SELECT" [ 99L ] inserted;
  let* skipped = fetch conn singleton_statement () in
  check_ids ~name:"source-free INSERT SELECT conflict" [] skipped;
  Lwt.return_unit
;;

let main () =
  let uri =
    if
      Int.(Stdlib.Array.length Stdlib.Sys.argv > 1)
      && String.equal Stdlib.Sys.argv.(1) "--postgres"
    then
      "postgresql://"
    else
      "sqlite3::memory:"
  in
  let* conn = Caqti_lwt_unix.connect (Uri.of_string uri) |> caqti_or_fail in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize (fun () -> run conn) (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
