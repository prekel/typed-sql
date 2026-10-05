open! Base
open Typed_sql
open Infix

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id person = Expr.column person id_column
  let name person = Expr.column person name_column
end

type input =
  { id : int64
  ; name : string
  }

let postgresql_getter_calls = ref 0
let sqlite_getter_calls = ref 0

let postgresql_statement =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Parameters id =
      params.column Person.id_column ~get:(fun input ->
        Int.incr postgresql_getter_calls;
        input.id)
    in
    params.query_many
      Query.(
        from Person.table
        |> where (fun person -> Person.id person =. id)
        |> select (fun person -> Projection.expr (Person.name person))))
;;

let sqlite_statement =
  Statement.with_parameters ~dialect:Dialect.sqlite (fun ~params ->
    let%map.Parameters name =
      params.column Person.name_column ~get:(fun input ->
        Int.incr sqlite_getter_calls;
        input.name)
    in
    params.query_many
      Query.(
        from Person.table
        |> where (fun person -> Person.name person =. name)
        |> select (fun person -> Projection.expr (Person.name person))))
;;

let statement : (input, string list, Dialect.both) Statement.t =
  Statement.choose_dialect ~postgresql:postgresql_statement ~sqlite:sqlite_statement
;;

let input_selected_postgresql_statement =
  Statement.choose
    ~when_:(fun input -> Int64.equal input.id 7L)
    ~if_true:postgresql_statement
    ~if_false:postgresql_statement
;;

let statement_with_input_selected_postgresql_branch =
  Statement.choose_dialect
    ~postgresql:input_selected_postgresql_statement
    ~sqlite:sqlite_statement
;;

let%expect_test "chooses the PostgreSQL statement without input" =
  Statement.sql_exn ~dialect:Postgresql statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name"
    FROM "people" AS t0
    WHERE
      (t0."id" = $1)
    |}]
;;

let%expect_test "chooses the SQLite statement without input" =
  Statement.sql_exn ~dialect:Sqlite statement |> Stdlib.print_endline;
  [%expect
    {|
    SELECT
      t0."name"
    FROM "people" AS t0
    WHERE
      (t0."name" = ?1)
    |}]
;;

let%test "an unselected input branch does not require input" =
  Result.is_ok
    (Statement.sql ~dialect:Sqlite statement_with_input_selected_postgresql_branch)
;;

let%test "a selected input branch requires input" =
  match
    Statement.sql ~dialect:Postgresql statement_with_input_selected_postgresql_branch
  with
  | Error Statement.Dynamic_input_required -> true
  | Ok _ | Error _ -> false
;;

let%test_unit "PostgreSQL resolution binds only the selected statement" =
  postgresql_getter_calls := 0;
  sqlite_getter_calls := 0;
  ignore
    (Statement.sql_exn ~dialect:Postgresql ~input:{ id = 7L; name = "Ada" } statement);
  assert (Int.(!postgresql_getter_calls = 1));
  assert (Int.(!sqlite_getter_calls = 0))
;;

let%test_unit "SQLite resolution binds only the selected statement" =
  postgresql_getter_calls := 0;
  sqlite_getter_calls := 0;
  ignore (Statement.sql_exn ~dialect:Sqlite ~input:{ id = 7L; name = "Ada" } statement);
  assert (Int.(!postgresql_getter_calls = 0));
  assert (Int.(!sqlite_getter_calls = 1))
;;
