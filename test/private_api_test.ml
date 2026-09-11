open! Base
open Typed_sql_private
open Expr.Infix
module A = Ast

let source source_id : A.source =
  { source_id; schema = None; table = Identifier.of_string_exn "items" }
;;

let column source_id =
  A.Column
    { source_id
    ; name = Identifier.of_string_exn "id"
    ; db_type = Db_type.Pack Db_type.int
    }
;;

let select : A.select =
  { source = source 0
  ; joins = []
  ; projection = [ column 0 ]
  ; where_ = None
  ; order_by = []
  ; limit = None
  ; offset = None
  }
;;

let assignment : A.assignment =
  { source_id = 0
  ; column = Identifier.of_string_exn "id"
  ; value = A.Expression (A.Param (Db_type.Value (Db_type.int, 7)))
  }
;;

let command kind assignments : A.command =
  let assignments, rows =
    match kind with
    | A.Insert -> [], [ assignments ]
    | A.Update -> assignments, []
    | A.Delete -> [], []
  in
  { kind
  ; source = source 0
  ; assignments
  ; rows
  ; from = []
  ; conflict = None
  ; where_ = None
  }
;;

let print_validation = function
  | Ok () -> failwith "expected validation error"
  | Error error -> Stdlib.print_endline (Compile_error.to_string error)
;;

let ok_exn result =
  result |> Result.map_error ~f:Compile_error.to_string |> Result.ok_or_failwith
;;

let%expect_test "private inspection preserves public query types and source identity" =
  let table : unit Table.t = Table.v_exn "items" in
  let id = Column.v_exn table "id" Db_type.int in
  let builder = Query.(from table |> where (fun row -> Expr.column row id =$ 7)) in
  let ast = Query.(ast builder) in
  let original =
    Query.(builder |> select (fun row -> Projection.expr (Expr.column row id)))
  in
  let projection = Result_query.projection original in
  let ast = { ast with A.projection = Projection.expressions projection } in
  let rebuilt = Result_query.create (A.Select ast) projection in
  let compile query = Compiler.compile ~dialect:Dialect.Sqlite query |> ok_exn in
  let original, rebuilt = compile original, compile rebuilt in
  assert (Shape.equal (Compiled_query.shape original) (Compiled_query.shape rebuilt));
  (match Projection.expressions projection with
   | [ A.Column { source_id; _ } ] -> assert (Int.equal source_id ast.source.source_id)
   | _ -> failwith "unexpected projection");
  Stdlib.print_endline (Compiled_query.sql rebuilt);
  [%expect {| SELECT t0."id" FROM "items" AS t0 WHERE (t0."id" = ?1) |}];
  let reference = Table_ref.create table in
  let nullable = Nullable_table_ref.of_table_ref reference in
  assert (
    Int.equal (Table_ref.source_id reference) (Nullable_table_ref.source_id nullable))
;;

let%test_unit "normalization identities and idempotence" =
  let atom = A.Is_null (column 0) in
  let cases =
    [ A.And [], A.True
    ; A.Or [], A.False
    ; A.And [ A.True; atom; A.And [ A.True ] ], atom
    ; A.Or [ A.False; atom; A.Or [ A.False ] ], atom
    ; A.And [ atom; A.False ], A.False
    ; A.Or [ atom; A.True ], A.True
    ; A.Not A.True, A.False
    ; A.Not A.False, A.True
    ; A.Not (A.Not atom), atom
    ; A.Not atom, A.Not atom
    ; A.And [ atom; A.And [ atom; atom ] ], A.And [ atom; atom; atom ]
    ; A.Or [ atom; A.Or [ atom; atom ] ], A.Or [ atom; atom; atom ]
    ]
  in
  List.iter cases ~f:(fun (input, expected) ->
    let normalized = Normalizer.normalize_condition input in
    assert (Poly.equal normalized expected);
    assert (Poly.equal (Normalizer.normalize_condition normalized) normalized))
;;

let%expect_test "validator catches invalid select and JOIN scopes" =
  let validate query = Validator.result_query (A.Select query) |> print_validation in
  validate { select with projection = [] };
  [%expect {| SELECT projection must contain at least one expression |}];
  validate { select with limit = Some (-1) };
  [%expect {| LIMIT must be non-negative, got -1 |}];
  validate { select with offset = Some (-2) };
  [%expect {| OFFSET must be non-negative, got -2 |}];
  validate { select with projection = [ column 99 ] };
  [%expect {| expression references source #99, but the visible sources are 0 |}];
  validate { select with order_by = [ { expr = column 99; direction = A.Desc } ] };
  [%expect {| expression references source #99, but the visible sources are 0 |}];
  let first : A.join =
    { kind = A.Inner; source = source 1; on = A.Compare (A.Eq, column 0, column 1) }
  in
  let second : A.join =
    { kind = A.Left; source = source 2; on = A.Compare (A.Eq, column 1, column 2) }
  in
  Validator.result_query
    (A.Select { select with joins = [ first; second ]; projection = [ column 2 ] })
  |> ok_exn;
  validate
    { select with joins = [ { first with on = A.Is_not_null (column 2) }; second ] };
  [%expect {| expression references source #2, but the visible sources are 0, 1 |}]
;;

let%expect_test "validator catches invalid DML assignments and RETURNING" =
  let validate command = Validator.command command |> print_validation in
  validate (command A.Insert []);
  [%expect {| INSERT must assign at least one column |}];
  validate (command A.Update []);
  [%expect {| UPDATE must assign at least one column |}];
  validate (command A.Update [ assignment; assignment ]);
  [%expect {| column id is assigned more than once |}];
  validate (command A.Update [ { assignment with source_id = 99 } ]);
  [%expect {| assignment belongs to source #99, but the command targets source #0 |}];
  validate (command A.Update [ { assignment with value = A.Expression (column 99) } ]);
  [%expect {| expression references source #99, but the visible sources are 0 |}];
  validate { (command A.Delete []) with where_ = Some (A.Not (A.Is_null (column 99))) };
  [%expect {| expression references source #99, but the visible sources are 0 |}];
  let insert = command A.Insert [ assignment ] in
  Validator.result_query (A.Returning { command = insert; projection = [] })
  |> print_validation;
  [%expect {| SELECT projection must contain at least one expression |}];
  Validator.result_query (A.Returning { command = insert; projection = [ column 99 ] })
  |> print_validation;
  [%expect {| expression references source #99, but the visible sources are 0 |}];
  Validator.command insert |> ok_exn
;;

let%test "private commands reach compiler validation" =
  let invalid = command A.Update [] |> Command.create in
  match Compiler.compile_command ~dialect:Dialect.Sqlite invalid with
  | Error (Compile_error.Empty_assignments `Update) -> true
  | _ -> false
;;

let%expect_test "private constructors share opaque public types" =
  let expression : int Expr.t =
    Expr.create (A.Param (Db_type.Value (Db_type.int, 42))) Db_type.int
  in
  let condition : Condition.t = Condition.create (A.Is_not_null (Expr.node expression)) in
  (match Condition.node condition with
   | A.Is_not_null (A.Param _) -> ()
   | _ -> failwith "condition representation changed");
  let template : Template.t =
    Template.of_parts [ Template.Text "SELECT "; Template.Param 0 ]
  in
  let projection = Projection.expr expression in
  let shape : Shape.t = Shape.create (Template.shape_string template) in
  let parameters = [ Db_type.Value (Db_type.int, 42) ] in
  let compiled : int Compiled_query.t =
    Compiled_query.create ~dialect:Dialect.Sqlite ~template ~parameters ~projection ~shape
  in
  assert (Shape.equal shape (Compiled_query.shape compiled));
  Stdlib.print_endline (Compiled_query.sql compiled);
  [%expect {| SELECT ?1 |}]
;;

let%expect_test "lowering and rendering preserve bind values for both dialects" =
  let ast =
    A.Returning
      { command = command A.Insert [ assignment ]
      ; projection = [ column 0; A.Param (Db_type.Value (Db_type.text, "returned")) ]
      }
    |> Normalizer.result_query
  in
  Validator.result_query ast |> ok_exn;
  let render dialect =
    let lowered = Lower.result_query ~dialect ast |> ok_exn in
    let template, parameters = Renderer.result_query lowered in
    (match parameters with
     | [ Db_type.Value (first_type, first); Db_type.Value (second_type, second) ] ->
       (match Db_type.view first_type, Db_type.view second_type with
        | Db_type.Int, Db_type.Text ->
          assert (Int.equal first 7);
          assert (String.equal second "returned")
        | _ -> failwith "parameter types changed")
     | _ -> failwith "parameter count changed");
    Template.to_sql ~dialect template
  in
  Stdlib.print_endline (render Dialect.Postgresql);
  [%expect {| INSERT INTO "items" ("id") VALUES ($1) RETURNING "id", $2 |}];
  Stdlib.print_endline (render Dialect.Sqlite);
  [%expect {| INSERT INTO "items" ("id") VALUES (?1) RETURNING "id", ?2 |}]
;;
