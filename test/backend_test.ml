open! Base
open Typed_sql
open Infix
module B = Typed_sql_backend

let compile_exn
  : type row kind.
    Dialect.t -> (row, kind, Dialect.portable) Result_query.t -> row B.Compiled_query.t
  =
  fun dialect query ->
  let statement =
    Statement.Portable.query_many (fun _ -> query)
    |> Result.map_error ~f:(fun (error : Statement.definition_error) ->
      Compile_error.to_string error.error)
    |> Result.ok_or_failwith
  in
  match B.Statement.resolve ~dialect () statement with
  | Ok (B.Statement.Query_execution { cardinality = B.Statement.Many; compiled }) ->
    compiled
  | Ok (B.Statement.Query_execution _) -> failwith "query cardinality changed"
  | Error _ -> failwith "query resolution failed"
;;

let compile_command_exn dialect command =
  let statement =
    Statement.Portable.command (fun _ -> command)
    |> Result.map_error ~f:(fun (error : Statement.definition_error) ->
      Compile_error.to_string error.error)
    |> Result.ok_or_failwith
  in
  match B.Statement.resolve ~dialect () statement with
  | Ok (B.Statement.Command_execution compiled) -> compiled
  | Ok (B.Statement.Query_execution _) -> failwith "command resolved as a query"
  | Error _ -> failwith "command resolution failed"
;;

let%test_unit "query shape excludes values and generative source ids" =
  let table : unit Table.t = Table.v_exn "people" in
  let name = Column.v_exn table "name" Db_type.text in
  let make value =
    Query.(
      from table
      |> where (fun row -> Expr.column row name =$ value)
      |> select (fun row -> Projection.expr (Expr.column row name)))
    |> compile_exn Dialect.Postgresql
  in
  let first = make "Ada" in
  let second = make "Grace" in
  assert (B.Shape.equal (B.Compiled_query.shape first) (B.Compiled_query.shape second));
  assert (Int.(List.length (B.Compiled_query.parameters first) = 1))
;;

let%test_unit "backend template layout matches public canonical SQL" =
  let table : unit Table.t = Table.v_exn "people" in
  let name = Column.v_exn table "name" Db_type.text in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let compiled =
      Query.(
        from table
        |> where (fun row -> Expr.column row name =$ "Ada")
        |> select (fun row -> Projection.expr (Expr.column row name)))
      |> compile_exn dialect
    in
    let parameter index =
      match dialect with
      | Dialect.Postgresql -> Stdlib.Format.asprintf "$%d" (index + 1)
      | Dialect.Sqlite -> Stdlib.Format.asprintf "?%d" (index + 1)
    in
    let backend_sql =
      B.Template.map (B.Compiled_query.template compiled) ~text:Fn.id ~param:parameter
      |> Stdlib.Format.asprintf
           "%a"
           (Stdlib.Format.pp_print_list
              ~pp_sep:(fun _formatter () -> ())
              Stdlib.Format.pp_print_string)
    in
    assert (String.equal backend_sql (B.Compiled_query.sql compiled)))
;;

let%test "mapped codecs with the same name have distinct shapes" =
  let mapped () =
    Db_type.map
      ~name:"id"
      ~encode:(fun value -> Ok value)
      ~decode:(fun value -> Ok value)
      Db_type.int64
  in
  let make db_type =
    let table : unit Table.t = Table.v_exn "ids" in
    let column = Column.v_exn table "id" db_type in
    Query.(from table |> select (fun row -> Projection.expr (Expr.column row column)))
    |> compile_exn Dialect.Sqlite
    |> B.Compiled_query.shape
  in
  not (B.Shape.equal (make (mapped ())) (make (mapped ())))
;;

let%test_unit "command shapes expose their stable representation" =
  let table : unit Table.t = Table.v_exn "items" in
  let id = Column.v_exn table "id" Db_type.int64 in
  let compiled =
    Insert.(into table |> set id 1L |> command) |> compile_command_exn Dialect.Sqlite
  in
  let shape = B.Compiled_command.shape compiled in
  assert (
    String.equal (B.Shape.to_string shape) (Stdlib.Format.asprintf "%a" B.Shape.pp shape));
  assert (Int.(B.Shape.hash shape = B.Shape.hash shape))
;;

let%test_unit "UPSERT shape excludes values and bind slots follow SQL order" =
  let table : unit Table.t = Table.v_exn "items" in
  let id = Column.v_exn table "id" Db_type.int64 in
  let make dialect value filtered =
    Insert.(
      into table
      |> set id value
      |> on_conflict (Conflict_target.column id)
      |> do_update (fun ~existing ~excluded:_ ->
        let action = Conflict_update.(empty |> set id Int64.(value + 1L)) in
        if filtered then
          Conflict_update.(
            action |> where (Expr.column existing id >$ Int64.(value + 2L)))
        else
          action)
      |> returning (fun row ->
        Projection.pair
          (Expr.column row id)
          (Expr.constant Db_type.int64 Int64.(value + 3L))))
    |> compile_exn dialect
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let first = make dialect 10L true in
    let second = make dialect 20L true in
    let shape query = B.Compiled_query.shape query in
    assert (B.Shape.equal (shape first) (shape second));
    assert (not (B.Shape.equal (shape first) (shape (make dialect 10L false))));
    let values =
      B.Compiled_query.parameters first
      |> List.map ~f:(fun (B.Db_type.Value (codec, value)) ->
        match B.Db_type.view codec with
        | B.Db_type.Int64 -> (value : int64)
        | _ -> failwith "UPSERT parameter codec changed")
    in
    assert (List.equal Int64.equal values [ 10L; 11L; 12L; 13L ]);
    let param index =
      match dialect with
      | Dialect.Postgresql -> Stdlib.Format.asprintf "$%d" (index + 1)
      | Dialect.Sqlite -> Stdlib.Format.asprintf "?%d" (index + 1)
    in
    let backend_sql =
      B.Template.map (B.Compiled_query.template first) ~text:Fn.id ~param
      |> Stdlib.Format.asprintf
           "%a"
           (Stdlib.Format.pp_print_list
              ~pp_sep:(fun _formatter () -> ())
              Stdlib.Format.pp_print_string)
    in
    assert (String.equal backend_sql (B.Compiled_query.sql first)))
;;
