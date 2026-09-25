open! Base
open Typed_sql
open Infix

module Person = struct
  let table : unit Table.t = Table.v_exn "people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
end

module Predicate = struct
  type t =
    | At_least of int64
    | At_most of int64
    | Name of string
    | Ids of int64 list
    | And of t list
    | Or of t list
    | Not of t

  let rec condition row = function
    | At_least id -> Person.id row >=$ id
    | At_most id -> Person.id row <=$ id
    | Name name -> Person.name row =$ name
    | Ids ids -> Expr.in_ (Person.id row) ids
    | And predicates ->
      List.fold predicates ~init:Condition.true_ ~f:(fun acc p -> acc &&. condition row p)
    | Or predicates ->
      List.fold predicates ~init:Condition.false_ ~f:(fun acc p ->
        acc ||. condition row p)
    | Not p -> Condition.not_ (condition row p)
  ;;
end

module Search_people = struct
  module Input = struct
    type t =
      { predicate : Predicate.t
      ; maximum_rows : int
      }
  end

  let statement =
    Statement.Dynamic.Portable.query_many (fun (input : Input.t) ->
      Query.(
        from Person.table
        |> where (fun row -> Predicate.condition row input.predicate)
        |> limit input.maximum_rows
        |> select (fun row -> Projection.expr (Person.id row))))
  ;;
end

let sql dialect predicate =
  Statement.sql_exn
    ~dialect
    ~input:{ Search_people.Input.predicate; maximum_rows = 10 }
    Search_people.statement
;;

let%expect_test "at least comparison uses PostgreSQL syntax" =
  Stdlib.print_endline (sql Dialect.Postgresql (At_least 3L));
  [%expect
    {|
    SELECT
      t0."id"
    FROM "people" AS t0
    WHERE
      (t0."id" >= $1)
    LIMIT 10
    |}]
;;

let%expect_test "at least comparison uses SQLite syntax" =
  Stdlib.print_endline (sql Dialect.Sqlite (At_least 3L));
  [%expect
    {|
    SELECT
      t0."id"
    FROM "people" AS t0
    WHERE
      (t0."id" >= ?1)
    LIMIT 10
    |}]
;;

let%expect_test "at most comparison uses PostgreSQL syntax" =
  Stdlib.print_endline (sql Dialect.Postgresql (At_most 9L));
  [%expect
    {|
    SELECT
      t0."id"
    FROM "people" AS t0
    WHERE
      (t0."id" <= $1)
    LIMIT 10
    |}]
;;

let%expect_test "at most comparison uses SQLite syntax" =
  Stdlib.print_endline (sql Dialect.Sqlite (At_most 9L));
  [%expect
    {|
    SELECT
      t0."id"
    FROM "people" AS t0
    WHERE
      (t0."id" <= ?1)
    LIMIT 10
    |}]
;;

let%test_unit "nested predicates and variable IN preserve portable SQL" =
  List.iter
    [ Predicate.And []
    ; Or []
    ; Ids []
    ; Ids [ 1L ]
    ; Ids [ 1L; 2L; 3L ]
    ; And [ Name "Ada"; Or [ At_least 1L; Not (At_most 3L) ] ]
    ]
    ~f:(fun predicate ->
      let input = { Search_people.Input.predicate; maximum_rows = 10 } in
      let pg =
        Statement.sql_exn ~dialect:Dialect.Postgresql ~input Search_people.statement
      in
      let sqlite =
        Statement.sql_exn ~dialect:Dialect.Sqlite ~input Search_people.statement
      in
      assert (String.equal (String.tr pg ~target:'$' ~replacement:'?') sqlite))
;;

let%test_unit "callbacks are deferred, selected once, and exceptions propagate" =
  let calls = ref 0 in
  let dynamic =
    Statement.Dynamic.Portable.query_many (fun () ->
      Int.incr calls;
      Query.(from Person.table |> select (fun row -> Projection.expr (Person.id row))))
  in
  let static =
    Statement.Portable.query_many_exn (fun _ ->
      Query.(from Person.table |> select (fun row -> Projection.expr (Person.id row))))
  in
  (match Statement.sql ~dialect:Dialect.Sqlite dynamic with
   | Error Statement.Dynamic_input_required -> ()
   | _ -> failwith "dynamic statement exposed SQL without input");
  let dynamic_command =
    Statement.Dynamic.Portable.command (fun () ->
      Delete.(from Person.table |> all_rows |> command))
  in
  (match Statement.sql ~dialect:Dialect.Sqlite dynamic_command with
   | Error Statement.Dynamic_input_required -> ()
   | _ -> failwith "dynamic command exposed SQL without input");
  assert (Int.(!calls = 0));
  let chosen =
    Statement.choose ~when_:(fun () -> false) ~if_true:dynamic ~if_false:static
  in
  (match Statement.sql ~dialect:Dialect.Sqlite chosen with
   | Error Statement.Dynamic_input_required -> ()
   | _ -> failwith "chosen statement exposed SQL without input");
  (match Statement.sql_exn ~dialect:Dialect.Sqlite chosen with
   | exception Failure message ->
     assert (String.equal message "statement SQL shape requires input")
   | _ -> failwith "chosen statement did not require input");
  ignore (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:() chosen);
  assert (Int.(!calls = 0));
  let chosen =
    Statement.choose ~when_:(fun () -> true) ~if_true:dynamic ~if_false:static
  in
  ignore (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:() chosen);
  ignore (Statement.sql_exn ~dialect:Dialect.Postgresql ~input:() chosen);
  assert (Int.(!calls = 2));
  let strict_one =
    Statement.Dynamic.Portable.query_one (fun () ->
      Query.(
        from Person.table |> select_exactly_one (fun _ -> Projection.expr Expr.count_all)))
  in
  let strict_optional =
    Statement.Dynamic.Portable.query_optional (fun () ->
      Query.(
        from Person.table
        |> limit_one
        |> select (fun person -> Projection.expr (Person.id person))))
  in
  ignore (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:() strict_one);
  ignore (Statement.sql_exn ~dialect:Dialect.Sqlite ~input:() strict_optional);
  let raising = Statement.Dynamic.Portable.query_many (fun () -> raise Stdlib.Exit) in
  match Statement.sql ~dialect:Dialect.Sqlite ~input:() raising with
  | exception Stdlib.Exit -> ()
  | _ -> failwith "callback exception was swallowed"
;;

let%test_unit "dynamic compilation errors are explicit" =
  let input = { Search_people.Input.predicate = And []; maximum_rows = -1 } in
  (match Statement.sql ~dialect:Dialect.Sqlite ~input Search_people.statement with
   | Error (Compilation_error { dialect = Sqlite; error = Negative_limit -1 }) -> ()
   | _ -> failwith "missing compilation error");
  (match Statement.sql_exn ~dialect:Dialect.Sqlite ~input Search_people.statement with
   | exception Statement.Definition_error { error = Negative_limit -1; _ } -> ()
   | _ -> failwith "missing definition exception");
  let escaped = ref None in
  ignore
    Query.(
      from Person.table
      |> select (fun row ->
        escaped := Some row;
        Projection.expr (Person.id row)));
  let bad =
    Statement.Dynamic.Portable.query_many (fun () ->
      Query.(
        from Person.table
        |> select (fun _ -> Projection.expr (Person.id (Option.value_exn !escaped)))))
  in
  match Statement.sql ~dialect:Dialect.Sqlite ~input:() bad with
  | Error (Compilation_error { error = Foreign_source _; _ }) -> ()
  | _ -> failwith "escaped source was accepted"
;;
