open! Base
open Typed_sql
open Infix

let ok_exn result =
  Result.map_error result ~f:Compile_error.to_string |> Result.ok_or_failwith
;;

let error_exn = function
  | Error error -> error
  | Ok _ -> failwith "expected compilation error"
;;

let table : unit Table.t = Table.v_exn "items"
let id = Column.v_exn table "id" Db_type.int
let name = Column.nullable_v_exn table "name" Db_type.text
let projection row = Projection.expr (Expr.column row id)
let query () = Query.(from table)
let compile dialect query = Query.(select projection query) |> Compiler.compile ~dialect
let sql dialect query = compile dialect query |> ok_exn |> Compiled_query.sql

let%test_unit "identifier validation and descriptor accessors" =
  assert (Poly.equal (Identifier.of_string "") (Error `Empty));
  assert (Poly.equal (Identifier.of_string "bad\000name") (Error `Contains_nul));
  List.iter [ ""; "bad\000name" ] ~f:(fun value ->
    match Identifier.of_string_exn value with
    | exception Stdlib.Invalid_argument message -> assert (not (String.is_empty message))
    | _ -> failwith "invalid identifier accepted");
  let identifier =
    Identifier.of_string "quoted\"name"
    |> Result.map_error ~f:Identifier.error_to_string
    |> Result.ok_or_failwith
  in
  assert (Identifier.equal identifier (Identifier.of_string_exn "quoted\"name"));
  let descriptor = Table.v ~schema:identifier identifier in
  assert (Identifier.equal (Table.name descriptor) identifier);
  assert (Option.equal Identifier.equal (Table.schema descriptor) (Some identifier));
  let column = Column.v descriptor identifier Db_type.int in
  let nullable = Column.nullable_v descriptor identifier Db_type.text in
  assert (Identifier.equal (Column.name column) identifier);
  assert (Identifier.equal (Table.name (Column.table column)) identifier);
  assert (String.equal (Db_type.name (Column.db_type column)) "int");
  assert (String.equal (Db_type.name (Column.base_db_type nullable)) "text");
  assert (String.equal (Db_type.name (Column.db_type nullable)) "option(text)");
  let mapped = Db_type.map Db_type.int ~encode:Result.return ~decode:Result.return in
  assert (String.equal (Db_type.name mapped) "mapped(int)");
  List.iter
    [ Db_type.name Db_type.bool, "bool"
    ; Db_type.name Db_type.int64, "int64"
    ; Db_type.name Db_type.float, "float"
    ; Db_type.name Db_type.bytes, "bytes"
    ]
    ~f:(fun (actual, expected) -> assert (String.equal actual expected))
;;

let%test_unit "all public database types participate in query shapes" =
  let check : type a. a Db_type.t -> a -> unit =
    fun db_type value ->
    let table : unit Table.t = Table.v_exn "typed_values" in
    let column = Column.v_exn table "value" db_type in
    List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
      Query.(
        from table
        |> where (fun row -> Expr.column row column =$ value)
        |> select (fun row -> Projection.expr (Expr.column row column)))
      |> Compiler.compile ~dialect
      |> ok_exn
      |> ignore)
  in
  check Db_type.bool true;
  check Db_type.int 1;
  check Db_type.int64 1L;
  check Db_type.float 1.5;
  check Db_type.text "value";
  check Db_type.bytes (Bytes.of_string "value");
  check (Db_type.option Db_type.text) None;
  check
    (Db_type.map
       ~name:"positive"
       ~encode:(fun value ->
         if value > 0 then
           Ok value
         else
           Error "not positive")
       ~decode:(fun value ->
         if value > 0 then
           Ok value
         else
           Error "not positive")
       Db_type.int)
    1
;;

let%expect_test "public diagnostic printers" =
  Stdlib.Format.printf "%a@." Identifier.pp (Identifier.of_string_exn "items");
  [%expect {| items |}];
  Stdlib.print_endline (Identifier.error_to_string `Empty);
  [%expect {| SQL identifier must not be empty |}];
  Stdlib.print_endline (Identifier.error_to_string `Contains_nul);
  [%expect {| SQL identifier must not contain a NUL byte |}];
  Stdlib.Format.printf "%a@." Affected_rows.pp (Affected_rows.Known 2);
  [%expect {| 2 |}];
  Stdlib.Format.printf "%a@." Affected_rows.pp Affected_rows.Unknown;
  [%expect {| unknown |}];
  Stdlib.Format.printf
    "%a@."
    Compile_error.pp
    (Compile_error.Invalid_assignment_source { expected = 1; actual = 2 });
  [%expect {| assignment belongs to source #2, but the command targets source #1 |}];
  Stdlib.Format.printf
    "%a@."
    Compile_error.pp
    (Compile_error.Foreign_source { visible = [ 1; 2 ]; actual = 3 });
  [%expect {| expression references source #3, but the visible sources are 1, 2 |}]
;;

let%test_unit "condition identities preserve compiled SQL for both dialects" =
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let atom = Expr.param Db_type.int 1 =$ 1 in
    let other = Expr.param Db_type.int 2 <>$ 3 in
    let render predicate = sql dialect Query.(query () |> where (fun _ -> predicate)) in
    List.iter
      [ Condition.true_ &&. atom, atom
      ; atom &&. Condition.true_, atom
      ; Condition.false_ ||. atom, atom
      ; atom ||. Condition.false_, atom
      ; Condition.true_ &&. Condition.true_, Condition.true_
      ; Condition.false_ ||. Condition.false_, Condition.false_
      ; atom &&. Condition.false_, Condition.false_
      ; Condition.true_ ||. atom, Condition.true_
      ; Condition.not_ Condition.true_, Condition.false_
      ; Condition.not_ Condition.false_, Condition.true_
      ; Condition.not_ (Condition.not_ atom), atom
      ; atom &&. other &&. atom, atom &&. (other &&. atom)
      ; atom ||. other ||. atom, atom ||. (other ||. atom)
      ]
      ~f:(fun (left, right) -> assert (String.equal (render left) (render right)));
    assert (String.equal (render Condition.true_) (sql dialect (query ()))))
;;

let%expect_test "null checks, NOT, OR and multiple sort keys" =
  let query =
    Query.(
      query ()
      |> where (fun row ->
        Expr.is_null (Expr.column row name)
        ||. Condition.not_ (Expr.is_not_null (Expr.to_nullable (Expr.column row id))))
      |> where_opt (Some 0) ~f:(fun row value -> Expr.column row id >$ value)
      |> order_by (fun row -> Expr.column row name) `Asc
      |> order_by (fun row -> Expr.column row id) `Desc
      |> limit 3
      |> offset 1)
  in
  Stdlib.print_endline (sql Dialect.Postgresql query);
  [%expect
    {| SELECT t0."id" FROM "items" AS t0 WHERE (((t0."name" IS NULL) OR (NOT (t0."id" IS NOT NULL))) AND (t0."id" > $1)) ORDER BY t0."name" ASC, t0."id" DESC LIMIT 3 OFFSET 1 |}];
  Stdlib.print_endline (sql Dialect.Sqlite query);
  [%expect
    {| SELECT t0."id" FROM "items" AS t0 WHERE (((t0."name" IS NULL) OR (NOT (t0."id" IS NOT NULL))) AND (t0."id" > ?1)) ORDER BY t0."name" ASC, t0."id" DESC LIMIT 3 OFFSET 1 |}]
;;

let%test_unit "expression operators agree with bound-value operators" =
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let left = Expr.param Db_type.int 1 in
    let right = Expr.param Db_type.int 2 in
    let render condition = sql dialect Query.(query () |> where (fun _ -> condition)) in
    List.iter
      [ left =. right, left =$ 2
      ; left <>. right, left <>$ 2
      ; left <. right, left <$ 2
      ; left <=. right, left <=$ 2
      ; left >. right, left >$ 2
      ; left >=. right, left >=$ 2
      ; ( Expr.param Db_type.text "a" =~. Expr.param Db_type.text "%"
        , Expr.param Db_type.text "a" =~$ "%" )
      ]
      ~f:(fun (a, b) -> assert (String.equal (render a) (render b))))
;;

let%test_unit "foreign sources are rejected in projection, sorting, JOIN and DML" =
  let escaped = ref None in
  let _ =
    Query.(
      from table
      |> select (fun row ->
        escaped := Some row;
        projection row))
  in
  let foreign = Option.value_exn !escaped in
  let expression = Expr.column foreign id in
  let check result =
    match error_exn result with
    | Compile_error.Foreign_source { visible; actual } ->
      assert (not (List.mem visible actual ~equal:Int.equal))
    | _ -> failwith "expected foreign source"
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    check
      (Query.(query () |> select (fun _ -> Projection.expr expression))
       |> Compiler.compile ~dialect);
    List.iter
      [ Query.(query () |> order_by (fun _ -> expression) `Asc)
      ; Query.(query () |> where (fun row -> Expr.column row id =. expression))
      ; Query.(
          query ()
          |> where (fun _ -> Condition.not_ (Expr.is_null (Expr.to_nullable expression))))
      ]
      ~f:(fun query -> check (compile dialect query));
    check
      (Query.(
         query ()
         |> inner_join table ~on:(fun _ _ -> expression =$ 0)
         |> select (fun _ -> Projection.expr expression))
       |> Compiler.compile ~dialect);
    check
      (Compiler.compile_command
         ~dialect
         (Insert.into table |> Insert.set_expr id expression |> Insert.command));
    check
      (Compiler.compile_command
         ~dialect
         (Update.table table
          |> Update.set_expr id expression
          |> Update.all_rows
          |> Update.command));
    check
      (Compiler.compile_command
         ~dialect
         (Delete.from table |> Delete.where (fun _ -> expression =$ 0) |> Delete.command));
    check
      (Compiler.compile
         ~dialect
         (Insert.into table
          |> Insert.set id 1
          |> Insert.returning (fun _ -> Projection.expr expression))))
;;

let%expect_test "invalid DML and pagination diagnostics" =
  let print_result result =
    Stdlib.Format.printf "%a@." Compile_error.pp (error_exn result)
  in
  print_result
    (Compiler.compile_command
       ~dialect:Dialect.Sqlite
       (Insert.into table |> Insert.command));
  [%expect {| INSERT must assign at least one column |}];
  print_result
    (Compiler.compile_command
       ~dialect:Dialect.Sqlite
       (Update.table table |> Update.all_rows |> Update.command));
  [%expect {| UPDATE must assign at least one column |}];
  print_result
    (Compiler.compile_command
       ~dialect:Dialect.Sqlite
       (Insert.into table |> Insert.set id 1 |> Insert.set id 2 |> Insert.command));
  [%expect {| column id is assigned more than once |}];
  print_result
    (Compiler.compile
       ~dialect:Dialect.Sqlite
       (Delete.from table
        |> Delete.all_rows
        |> Delete.returning (fun _ -> Projection.return ())));
  [%expect {| SELECT projection must contain at least one expression |}];
  print_result (compile Dialect.Sqlite Query.(query () |> offset (-1)));
  [%expect {| OFFSET must be non-negative, got -1 |}]
;;

let%expect_test "multi-assignment UPDATE and DELETE RETURNING" =
  let updated =
    Update.table table
    |> Update.set_expr id (Expr.param Db_type.int 2)
    |> Update.set name (Some "updated")
    |> Update.where (fun row -> Expr.column row id >$ 0)
    |> Update.where (fun row -> Expr.column row id <$ 3)
    |> Update.returning projection
  in
  let deleted =
    Delete.from table
    |> Delete.where (fun row -> Expr.column row id >=$ 0)
    |> Delete.where (fun row -> Expr.column row id <=$ 3)
    |> Delete.returning projection
  in
  let render dialect query =
    Compiler.compile ~dialect query |> ok_exn |> Compiled_query.sql
  in
  Stdlib.print_endline (render Dialect.Postgresql updated);
  [%expect
    {| UPDATE "items" SET "id" = $1, "name" = $2 WHERE (("id" > $3) AND ("id" < $4)) RETURNING "id" |}];
  Stdlib.print_endline (render Dialect.Sqlite updated);
  [%expect
    {| UPDATE "items" SET "id" = ?1, "name" = ?2 WHERE (("id" > ?3) AND ("id" < ?4)) RETURNING "id" |}];
  Stdlib.print_endline (render Dialect.Postgresql deleted);
  [%expect {| DELETE FROM "items" WHERE (("id" >= $1) AND ("id" <= $2)) RETURNING "id" |}];
  Stdlib.print_endline (render Dialect.Sqlite deleted);
  [%expect {| DELETE FROM "items" WHERE (("id" >= ?1) AND ("id" <= ?2)) RETURNING "id" |}]
;;

let%test_unit "builders are immutable and all_rows clears filters" =
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let base = query () in
    let filtered = Query.(base |> where (fun row -> Expr.column row id =$ 1)) in
    assert (not (String.equal (sql dialect base) (sql dialect filtered)));
    let compiled = compile dialect base |> ok_exn in
    assert (Poly.equal (Compiled_query.dialect compiled) dialect);
    let render command =
      let compiled = Compiler.compile_command ~dialect command |> ok_exn in
      assert (Poly.equal (Compiled_command.dialect compiled) dialect);
      Compiled_command.sql compiled
    in
    let update = Update.table table |> Update.set id 1 in
    assert (
      String.equal
        (render
           (update
            |> Update.where (fun _ -> Condition.false_)
            |> Update.all_rows
            |> Update.command))
        (render (update |> Update.all_rows |> Update.command)));
    assert (
      String.equal
        (render
           (Delete.from table
            |> Delete.where (fun _ -> Condition.false_)
            |> Delete.all_rows
            |> Delete.command))
        (render (Delete.from table |> Delete.all_rows |> Delete.command))))
;;
