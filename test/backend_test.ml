open! Base
open Typed_sql
open Infix
module B = Typed_sql_backend

let compile_exn
  : type row kind cardinality.
    Dialect.t
    -> (row, kind, cardinality, Dialect.portable) Result_query.t
    -> row B.Compiled_query.t
  =
  fun dialect query ->
  let statement = Statement.query_many ~dialect:Dialect.portable query in
  match B.Statement.resolve ~dialect () statement with
  | Ok (B.Statement.Query_execution { cardinality = B.Statement.Many; compiled }) ->
    compiled
  | Ok (B.Statement.Query_execution _) -> failwith "query cardinality changed"
  | Error _ -> failwith "query resolution failed"
;;

let compile_command_exn dialect command =
  let statement = Statement.command ~dialect:Dialect.portable command in
  match B.Statement.resolve ~dialect () statement with
  | Ok (B.Statement.Command_execution compiled) -> compiled
  | Ok (B.Statement.Query_execution _) -> failwith "command resolved as a query"
  | Error _ -> failwith "command resolution failed"
;;

let%test "backend rejects PostgreSQL for a SQLite-only statement" =
  let statement =
    Statement.query_one
      ~dialect:Dialect.sqlite
      (Query.select_one (Expr.constant Db_type.int 1))
  in
  match B.Statement.resolve ~dialect:Dialect.Postgresql () statement with
  | Error B.Statement.Dialect_mismatch -> true
  | Ok _ | Error _ -> false
;;

let%test "backend rejects PostgreSQL for a SQLite-only dynamic statement" =
  let statement =
    Statement.Dynamic.query_one ~dialect:Dialect.sqlite (fun () ->
      Query.select_one (Expr.constant Db_type.int 1))
  in
  match B.Statement.resolve ~dialect:Dialect.Postgresql () statement with
  | Error B.Statement.Dialect_mismatch -> true
  | Ok _ | Error _ -> false
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

let%test "numeric codecs expose an exact adapter view" =
  let table : unit Table.t = Table.v_exn "numeric_values" in
  let numeric_value = Decimal.of_string "1.25" |> Option.value_exn in
  let query =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map value = params.expr Db_type.numeric ~get:(fun () -> numeric_value) in
      params.query_many Query.(from table |> select (fun _ -> Projection.expr value)))
  in
  match B.Statement.resolve ~dialect:Dialect.Postgresql () query with
  | Ok (B.Statement.Query_execution { compiled; _ }) ->
    (match B.Compiled_query.parameters compiled with
     | [ B.Db_type.Value (db_type, _) ] ->
       (match B.Db_type.view db_type with
        | B.Db_type.Numeric -> true
        | _ -> false)
     | _ -> false)
  | Error _ -> false
;;

let%test_module "PostgreSQL nullable pagination binds typed optional values" =
  (module struct
    type inner =
      { minimum_id : int
      ; limit : int option
      ; offset : int option
      }

    type input = { inner : inner }

    let table : unit Table.t = Table.v_exn "items"
    let id = Column.v_exn table "id" Db_type.int

    let statement =
      Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
        let open Statement.Parameters.Let_syntax in
        let%map minimum_id =
          params.expr Db_type.int ~get:(fun input -> input.inner.minimum_id)
        and maximum_rows =
          params.non_negative_int_opt ~name:"limit" ~get:(fun input -> input.inner.limit)
        and start_at =
          params.non_negative_int_opt ~name:"offset" ~get:(fun input ->
            input.inner.offset)
        in
        params.query_many
          Query.(
            from table
            |> where (fun row -> Expr.column row id >=. minimum_id)
            |> Postgresql.Query.limit_param_opt maximum_rows
            |> Postgresql.Query.offset_param_opt start_at
            |> select (fun row -> Projection.expr (Expr.column row id))))
    ;;

    let parameters inner =
      match B.Statement.resolve ~dialect:Dialect.Postgresql { inner } statement with
      | Ok (B.Statement.Query_execution { compiled; _ }) ->
        Some (B.Compiled_query.parameters compiled)
      | Error _ -> None
    ;;

    let is_int expected = function
      | B.Db_type.Value (db_type, value) ->
        (match B.Db_type.view db_type with
         | B.Db_type.Int -> Int.equal value expected
         | _ -> false)
    ;;

    let is_optional_int (expected : int option) = function
      | B.Db_type.Value (db_type, value) ->
        (match B.Db_type.view db_type with
         | B.Db_type.Option inner_type ->
           (match B.Db_type.view inner_type with
            | B.Db_type.Int -> Option.equal Int.equal value expected
            | _ -> false)
         | _ -> false)
    ;;

    let%test "None binds SQL NULL for limit and offset" =
      match parameters { minimum_id = 3; limit = None; offset = None } with
      | Some [ minimum_id; limit; offset ] ->
        is_int 3 minimum_id && is_optional_int None limit && is_optional_int None offset
      | None | Some _ -> false
    ;;

    let%test "Some values bind as nullable integers" =
      match parameters { minimum_id = 3; limit = Some 10; offset = Some 20 } with
      | Some [ minimum_id; limit; offset ] ->
        is_int 3 minimum_id
        && is_optional_int (Some 10) limit
        && is_optional_int (Some 20) offset
      | None | Some _ -> false
    ;;
  end)
;;

let%test "list-array parameter exposes a reversible backend codec" =
  let descriptor = Db_type.Postgresql.array_list Db_type.int64 in
  let statement =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map value = params.expr descriptor ~get:Fn.id in
      params.query_one (Query.select_one value))
  in
  match
    ( B.Statement.resolve ~dialect:Dialect.Postgresql [ 1L; 2L ] statement
    , B.Statement.resolve ~dialect:Dialect.Postgresql [] statement )
  with
  | ( Ok (B.Statement.Query_execution { compiled; _ })
    , Ok (B.Statement.Query_execution { compiled = empty; _ }) ) ->
    B.Shape.equal (B.Compiled_query.shape compiled) (B.Compiled_query.shape empty)
    && Int.(List.length (B.Compiled_query.parameters compiled) = 1)
    &&
      (match B.Compiled_query.parameters compiled with
      | [ B.Db_type.Value (db_type, value) ] ->
        (match B.Db_type.view db_type with
         | B.Db_type.Array { encode; decode } ->
           (match encode value with
            | Error _ -> false
            | Ok encoded ->
              String.equal encoded {|{"1","2"}|}
              && (match decode encoded with
                  | Error _ -> false
                  | Ok decoded ->
                    (match encode decoded with
                     | Ok roundtrip -> String.equal roundtrip encoded
                     | Error _ -> false))
              && Result.is_error (decode "{1,NULL}"))
         | _ -> false)
      | _ -> false)
  | _ -> false
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
