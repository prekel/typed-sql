open! Base
open Typed_sql_private
open Expr.Infix
module A = Ast
module Raw_compiler = Compiler

module Compiler = struct
  let values parameters =
    List.map parameters ~f:(function
      | A.Value value -> value
      | A.Slot _ -> failwith "unexpected statement slot")
  ;;

  let compile ~dialect query =
    Raw_compiler.compile_query_plan ~dialect:(Dialect.kind dialect) query
    |> Result.map ~f:(fun (plan : _ Raw_compiler.query_plan) ->
      Compiled_query.create
        ~dialect:plan.dialect
        ~template:plan.template
        ~parameters:(values plan.parameters)
        ~projection:plan.projection
        ~shape:plan.shape)
  ;;

  let compile_command ~dialect command =
    Raw_compiler.compile_command_plan ~dialect:(Dialect.kind dialect) command
    |> Result.map ~f:(fun (plan : Raw_compiler.command_plan) ->
      Compiled_command.create
        ~dialect:plan.dialect
        ~template:plan.template
        ~parameters:(values plan.parameters)
        ~shape:plan.shape)
  ;;
end

let source source_id : A.source =
  { source_id
  ; kind = A.Table { schema = None; table = Identifier.of_string_exn "items" }
  }
;;

let column source_id =
  A.Column
    { source_id
    ; name = Identifier.of_string_exn "id"
    ; db_type = Db_type.Pack Db_type.int
    }
;;

let select : A.select =
  { ctes = []
  ; source = source 0
  ; joins = []
  ; distinct = false
  ; projection = [ column 0 ]
  ; where_ = None
  ; group_by = []
  ; having = None
  ; order_by = []
  ; limit = None
  ; offset = None
  }
;;

let assignment : A.assignment =
  { source_id = 0
  ; column = Identifier.of_string_exn "id"
  ; value = A.Expression (A.Param (A.Value (Db_type.Value (Db_type.int, 7))))
  }
;;

let conflict_column ?(source_id = 0) column : A.conflict_target_column =
  { target_source_id = source_id; target_column = column }
;;

let command kind assignments : A.command =
  let assignments, rows =
    match kind with
    | A.Insert -> [], [ assignments ]
    | A.Update -> assignments, []
    | A.Delete -> [], []
  in
  { ctes = []
  ; kind
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

let rec equal_condition left right =
  match left, right with
  | A.True, A.True | A.False, A.False -> true
  | A.Is_null left, A.Is_null right -> Validator.same_column left right
  | A.And left, A.And right | A.Or left, A.Or right ->
    List.equal equal_condition left right
  | A.Not left, A.Not right -> equal_condition left right
  | _ -> false
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
  let rebuilt = Result_query.create_select (A.Simple ast) projection in
  let compile query = Compiler.compile ~dialect:Dialect.sqlite query |> ok_exn in
  let original, rebuilt = compile original, compile rebuilt in
  assert (Shape.equal (Compiled_query.shape original) (Compiled_query.shape rebuilt));
  (match Projection.expressions projection with
   | [ A.Column { source_id; _ } ] -> assert (Int.(source_id = ast.source.source_id))
   | _ -> failwith "unexpected projection");
  Stdlib.print_endline (Compiled_query.sql rebuilt);
  [%expect
    {|
    SELECT
      t0."id"
    FROM "items" AS t0
    WHERE
      (t0."id" = ?1)
    |}];
  let reference = Table_ref.create table in
  let nullable = Nullable_table_ref.of_table_ref reference in
  assert (Int.(Table_ref.source_id reference = Nullable_table_ref.source_id nullable))
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
    assert (equal_condition normalized expected);
    assert (equal_condition (Normalizer.normalize_condition normalized) normalized))
;;

let%expect_test "validator catches invalid select and JOIN scopes" =
  let validate query =
    Validator.result_query (A.Select (A.Simple query)) |> print_validation
  in
  validate { select with projection = [] };
  [%expect {| SELECT projection must contain at least one expression |}];
  validate { select with limit = Some (A.Literal (-1)) };
  [%expect {| LIMIT must be non-negative, got -1 |}];
  validate { select with offset = Some (A.Literal (-2)) };
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
    (A.Select
       (A.Simple { select with joins = [ first; second ]; projection = [ column 2 ] }))
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

let cte_source ~cte_id source_id : A.source = { source_id; kind = A.Cte cte_id }

let text_column source_id =
  A.Column
    { source_id
    ; name = Identifier.of_string_exn "text_value"
    ; db_type = Db_type.Pack Db_type.text
    }
;;

let int_relation (source : A.source) : A.relation =
  let output = column source.Ast.source_id in
  { A.query = A.Simple { select with source; projection = [ output ] }
  ; columns = [ output ]
  ; column_types = [ Db_type.Pack Db_type.int ]
  ; result_types = [ Db_type.Pack Db_type.int ]
  }
;;

let text_relation (source : A.source) : A.relation =
  let output = text_column source.Ast.source_id in
  { A.query = A.Simple { select with source; projection = [ output ] }
  ; columns = [ output ]
  ; column_types = [ Db_type.Pack Db_type.text ]
  ; result_types = [ Db_type.Pack Db_type.text ]
  }
;;

let recursive_cte ~cte_id ~step : A.cte =
  { cte_id
  ; columns = [ column 100 ]
  ; column_types = [ Db_type.Pack Db_type.int ]
  ; result_types = [ Db_type.Pack Db_type.int ]
  ; materialization = None
  ; body =
      A.Recursive_body
        { union = A.Recursive_union_all; anchor = int_relation (source 1); step }
  }
;;

let query_with_cte (cte : A.cte) : A.result_query =
  let result_source = cte_source ~cte_id:cte.Ast.cte_id 50 in
  A.Select
    (A.Simple
       { select with
         ctes = [ cte ]
       ; source = result_source
       ; projection = [ column result_source.source_id ]
       })
;;

let expect_unknown_cte expected = function
  | Error (Compile_error.Unknown_cte actual) -> assert (Int.(actual = expected))
  | Error error -> failwith ("expected Unknown_cte, got " ^ Compile_error.to_string error)
  | Ok () -> failwith "unknown CTE was accepted"
;;

let expect_invalid_recursive_reference expected = function
  | Error (Compile_error.Invalid_recursive_reference actual) ->
    assert (Int.(actual = expected))
  | Error error ->
    failwith ("expected Invalid_recursive_reference, got " ^ Compile_error.to_string error)
  | Ok () -> failwith "invalid recursive CTE was accepted"
;;

let%test_unit "validator rejects unavailable CTEs in nested scalar and EXISTS queries" =
  let cte_id = 701 in
  let nested_source = cte_source ~cte_id 1 in
  let nested =
    { select with
      source = nested_source
    ; projection = [ column nested_source.source_id ]
    ; limit = Some (A.Literal 1)
    }
  in
  let scalar =
    A.Select (A.Simple { select with projection = [ A.Scalar_subquery nested ] })
  in
  expect_unknown_cte cte_id (Validator.result_query scalar);
  let exists = A.Select (A.Simple { select with where_ = Some (A.Exists nested) }) in
  expect_unknown_cte cte_id (Validator.result_query exists)
;;

let%test_unit "validator rejects incompatible recursive anchor and step types" =
  let cte_id = 702 in
  let step = text_relation (cte_source ~cte_id 2) in
  let cte = recursive_cte ~cte_id ~step in
  match Validator.result_query (query_with_cte cte) with
  | Error (Compile_error.Mismatched_set_projection _) -> ()
  | Error error ->
    failwith ("expected Mismatched_set_projection, got " ^ Compile_error.to_string error)
  | Ok () -> failwith "recursive CTE accepted incompatible type vectors"
;;

let%test_unit "validator rejects extra and nested recursive self-references" =
  let cte_id = 703 in
  let direct_self = cte_source ~cte_id 2 in
  let extra_self = cte_source ~cte_id 3 in
  let direct_step =
    { (int_relation direct_self) with
      query =
        A.Simple
          { select with
            source = direct_self
          ; joins = [ { kind = A.Inner; source = extra_self; on = A.True } ]
          ; projection = [ column direct_self.source_id ]
          }
    }
  in
  expect_invalid_recursive_reference
    cte_id
    (Validator.result_query (query_with_cte (recursive_cte ~cte_id ~step:direct_step)));
  let nested_self = cte_source ~cte_id 4 in
  let nested_relation = int_relation nested_self in
  let nested_source : A.source = { source_id = 3; kind = A.Derived nested_relation } in
  let nested_step =
    { (int_relation direct_self) with
      query =
        A.Simple
          { select with
            source = direct_self
          ; joins = [ { kind = A.Inner; source = nested_source; on = A.True } ]
          ; projection = [ column direct_self.source_id ]
          }
    }
  in
  expect_invalid_recursive_reference
    cte_id
    (Validator.result_query (query_with_cte (recursive_cte ~cte_id ~step:nested_step)))
;;

let%expect_test "validator rejects malformed private conflict clauses" =
  let id = Identifier.of_string_exn "id" in
  let insert = command A.Insert [ assignment ] in
  let validate conflict =
    Validator.command { insert with conflict = Some conflict } |> print_validation
  in
  validate (A.Do_nothing (Some []));
  [%expect {| ON CONFLICT target must contain at least one column |}];
  validate
    (A.Do_update
       { target = []
       ; excluded_source_id = 1
       ; where_ = None
       ; assignments = [ assignment ]
       });
  [%expect {| ON CONFLICT target must contain at least one column |}];
  validate
    (A.Do_update
       { target = [ conflict_column id; conflict_column id ]
       ; excluded_source_id = 1
       ; where_ = None
       ; assignments = [ assignment ]
       });
  [%expect {| ON CONFLICT target contains column id more than once |}];
  validate (A.Do_nothing (Some [ conflict_column ~source_id:99 id ]));
  [%expect {| ON CONFLICT target column belongs to source #99, expected source #0 |}];
  validate
    (A.Do_update
       { target = [ conflict_column id ]
       ; excluded_source_id = 1
       ; where_ = None
       ; assignments = [ assignment; assignment ]
       });
  [%expect {| column id is assigned more than once |}]
;;

let%test "private commands reach compiler validation" =
  let invalid = command A.Update [] |> Command.create in
  match Compiler.compile_command ~dialect:Dialect.sqlite invalid with
  | Error (Compile_error.Empty_assignments `Update) -> true
  | _ -> false
;;

let%test_unit "private UPSERT DEFAULT reaches dialect capability checking" =
  let ast =
    { (command A.Insert [ assignment ]) with
      conflict =
        Some
          (A.Do_update
             { target = [ conflict_column assignment.column ]
             ; excluded_source_id = 1
             ; assignments = [ { assignment with value = A.Default } ]
             ; where_ = None
             })
    }
  in
  let command = Command.create ast in
  ignore (Compiler.compile_command ~dialect:Dialect.postgresql command |> ok_exn);
  match Compiler.compile_command ~dialect:Dialect.sqlite command with
  | Error (Compile_error.Unsupported_operation { operation; dialect = Dialect.Sqlite }) ->
    assert (String.equal operation "ON CONFLICT DO UPDATE SET DEFAULT")
  | _ -> failwith "SQLite accepted an UPSERT DEFAULT assignment"
;;

let%expect_test "private constructors share opaque public types" =
  let expression : (int, Dialect.portable) Expr.t =
    Expr.create (A.Param (A.Value (Db_type.Value (Db_type.int, 42)))) Db_type.int
  in
  let condition : Dialect.portable Condition.t =
    Condition.create (A.Is_not_null (Expr.node expression))
  in
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
    Compiled_query.create
      ~dialect:Dialect.Sqlite
      ~template
      ~parameters
      ~projection:(Projection.erase projection)
      ~shape
  in
  assert (Shape.equal shape (Compiled_query.shape compiled));
  Stdlib.print_endline (Compiled_query.sql compiled);
  [%expect {| SELECT ?1 |}]
;;

let%test_unit "template layout does not affect shape identity" =
  let compact = Template.of_parts [ Template.Text "SELECT "; Template.Param 0 ] in
  let formatted =
    Template.of_parts
      [ Template.Text "SELECT"
      ; Template.Nest (Template.of_parts [ Template.Break " "; Template.Param 0 ])
      ]
  in
  assert (String.equal (Template.shape_string compact) (Template.shape_string formatted));
  assert (
    not
      (String.equal
         (Template.to_sql ~dialect:Dialect.Sqlite compact)
         (Template.to_sql ~dialect:Dialect.Sqlite formatted)))
;;

let%expect_test "lowering and rendering preserve bind values for both dialects" =
  let ast =
    A.Returning
      { command = command A.Insert [ assignment ]
      ; projection =
          [ column 0; A.Param (A.Value (Db_type.Value (Db_type.text, "returned"))) ]
      }
    |> Normalizer.result_query
  in
  Validator.result_query ast |> ok_exn;
  let render dialect =
    let lowered = Lower.result_query ~dialect ast |> ok_exn in
    let template, parameters = Renderer.result_query lowered in
    (match parameters with
     | [ A.Value (Db_type.Value (first_type, first))
       ; A.Value (Db_type.Value (second_type, second))
       ] ->
       (match Db_type.view first_type, Db_type.view second_type with
        | Db_type.Int, Db_type.Text ->
          assert (Int.(first = 7));
          assert (String.equal second "returned")
        | _ -> failwith "parameter types changed")
     | _ -> failwith "parameter count changed");
    Template.to_sql ~dialect template
  in
  Stdlib.print_endline (render Dialect.Postgresql);
  [%expect
    {|
    INSERT INTO "items" (
      "id"
    )
    VALUES
      ($1)
    RETURNING
      "id",
      $2
    |}];
  Stdlib.print_endline (render Dialect.Sqlite);
  [%expect
    {|
    INSERT INTO "items" (
      "id"
    )
    VALUES
      (?1)
    RETURNING
      "id",
      ?2
    |}]
;;

let%test_unit "renderer totality covers malformed private AST diagnostics" =
  let render query =
    let template, _ = Renderer.result_query query in
    Template.to_sql ~dialect:Dialect.Sqlite template
  in
  assert (
    String.equal
      (render (A.Select (A.Simple { select with where_ = Some A.True })))
      "SELECT\n  t0.\"id\"\nFROM \"items\" AS t0\nWHERE\n  TRUE");
  assert (
    String.equal
      (render (A.Select (A.Simple { select with where_ = Some (A.And []) })))
      "SELECT\n  t0.\"id\"\nFROM \"items\" AS t0\nWHERE\n  ()");
  ignore
    (render (A.Returning { command = command A.Insert [ assignment ]; projection = [] }));
  ignore (Renderer.command (command A.Update []));
  ignore (Renderer.command (command A.Insert []));
  ignore
    (Renderer.render_insert_rows ~aliases:[ 0, "" ] ~columns:[] [] Renderer.initial_state)
;;

let%test_unit "internal helper boundary cases remain total" =
  (match Lower.condition ~dialect:Dialect.Sqlite A.True with
   | A.True -> ()
   | _ -> failwith "lowering changed a true condition");
  assert (Option.is_none (Normalizer.optional_condition (Some A.True)));
  ignore (Renderer.render_order_by ~aliases:[ 0, "t0" ] [] Renderer.initial_state);
  let single, _ =
    Renderer.render_condition_list
      ~aliases:[ 0, "t0" ]
      ~operator:"AND"
      [ A.True ]
      Renderer.initial_state
  in
  assert (String.equal (Template.to_sql ~dialect:Dialect.Sqlite single) "(TRUE)");
  let empty_conditions, _ =
    Renderer.render_conditions
      ~aliases:[ 0, "t0" ]
      ~operator:"AND"
      []
      Renderer.initial_state
  in
  assert (String.is_empty (Template.to_sql ~dialect:Dialect.Sqlite empty_conditions));
  assert (
    String.is_empty
      (Renderer.render_from_sources ~aliases:[] [] Renderer.initial_state
       |> fst
       |> Template.to_sql ~dialect:Dialect.Sqlite));
  let rendered_sources =
    let sources =
      Renderer.render_from_sources
        ~aliases:[ 0, "t0"; 1, "t1" ]
        [ source 0; source 1 ]
        Renderer.initial_state
      |> fst
    in
    Template.of_parts [ Template.Nest sources ] |> Template.to_sql ~dialect:Dialect.Sqlite
  in
  assert (String.equal rendered_sources "\"items\" AS t0,\n  \"items\" AS t1");
  assert (
    not
      (Validator.same_column
         (column 0)
         (A.Param (A.Value (Db_type.Value (Db_type.int, 0))))));
  let arithmetic = A.Arithmetic (A.Add, column 0, column 0) in
  assert (Validator.same_group_expression arithmetic arithmetic);
  List.iter [ A.Add; A.Subtract; A.Multiply; A.Divide ] ~f:(fun operator ->
    assert (Validator.same_arithmetic operator operator));
  assert (not (Validator.same_arithmetic A.Add A.Subtract));
  List.iter [ A.Lower; A.Upper; A.Length ] ~f:(fun function_ ->
    assert (Validator.same_string_function function_ function_));
  assert (not (Validator.same_string_function A.Lower A.Upper));
  assert (not (Validator.same_string_function A.Sqlite_length A.Sqlite_length));
  let concat = A.Concat (column 0, column 0) in
  assert (Validator.same_group_expression concat concat);
  let left : Validator.aggregate_analysis =
    { has_aggregate = false; nested_aggregate = false; grouped = true }
  in
  let right : Validator.aggregate_analysis =
    { has_aggregate = true; nested_aggregate = true; grouped = true }
  in
  assert (Validator.combine left right).nested_aggregate;
  assert (Validator.combine right left).nested_aggregate;
  let validate_subquery ~outer_visible:_ ~allow_empty:_ _ = Ok () in
  Validator.validate_condition ~validate_subquery ~visible:[] A.True |> ok_exn;
  ignore (Validator.analyze_condition ~groups:[] ~inside_aggregate:false A.True);
  let nested_count = A.Aggregate (A.Count (A.Aggregate (A.Count (column 0)))) in
  assert
    (Validator.analyze_expression ~groups:[] ~inside_aggregate:false nested_count)
      .nested_aggregate;
  match Validator.command { (command A.Insert []) with rows = [] } with
  | Error (Compile_error.Empty_assignments `Insert) -> ()
  | _ -> failwith "empty private INSERT was accepted"
;;

let%test_unit
    "lowering capability traversal and scalar aggregate proof cover private cases"
  =
  let parameter = A.Param (A.Value (Db_type.Value (Db_type.int, 1))) in
  let local_aggregate = A.Aggregate (A.Count (column 0)) in
  let nested_select = { select with having = Some A.True } in
  let expression =
    A.Case
      ( [ ( A.Compare (A.Eq, column 0, parameter)
          , A.Arithmetic (A.Add, A.String_function (A.Length, column 0), parameter) )
        ]
      , A.Concat (A.Aggregate (A.Count_distinct (column 0)), A.Scalar_subquery select) )
  in
  let condition =
    A.And
      [ A.Is_null expression
      ; A.Is_not_null expression
      ; A.In (expression, [ parameter ])
      ; A.Not_in (expression, [ parameter ])
      ; A.Between (expression, parameter, column 0)
      ; A.Exists select
      ; A.Not_exists select
      ; A.In_subquery (expression, select)
      ; A.Not_in_subquery (expression, select)
      ; A.Or [ A.False ]
      ; A.Not A.False
      ]
  in
  let join = { A.kind = A.Inner; source = source 1; on = condition } in
  let complete =
    { select with
      joins = [ join ]
    ; projection = [ expression ]
    ; where_ = Some condition
    ; group_by = [ expression ]
    ; having = Some condition
    ; order_by = [ { A.expr = expression; direction = A.Asc } ]
    }
  in
  assert (not (Lower.select_has_unsupported_having ~dialect:Dialect.Sqlite complete));
  assert (
    Lower.expression_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.Scalar_subquery nested_select));
  let bad_expression = A.Scalar_subquery nested_select in
  assert (
    Lower.expression_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.Arithmetic (A.Add, bad_expression, column 0)));
  assert (
    Lower.expression_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.Case ([ A.True, column 0 ], bad_expression)));
  assert (
    Lower.expression_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.Case ([ A.Exists nested_select, column 0 ], column 0)));
  assert (
    Lower.condition_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.Exists nested_select));
  assert (
    Lower.condition_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.Compare (A.Eq, bad_expression, column 0)));
  assert (
    Lower.condition_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.In (bad_expression, [ column 0 ])));
  assert (
    Lower.condition_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.In_subquery (parameter, nested_select)));
  assert (
    Lower.condition_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (A.In_subquery (bad_expression, select)));
  assert (
    Lower.select_has_unsupported_having
      ~dialect:Dialect.Sqlite
      { select with projection = [ bad_expression ]; group_by = [ column 0 ] });
  assert (
    Lower.select_has_unsupported_having
      ~dialect:Dialect.Sqlite
      { select with
        joins = [ { A.kind = A.Inner; source = source 1; on = A.Exists nested_select } ]
      ; projection = []
      });
  assert (
    Lower.select_has_unsupported_having
      ~dialect:Dialect.Sqlite
      { select with projection = []; where_ = Some (A.Exists nested_select) });
  assert (
    Lower.select_has_unsupported_having
      ~dialect:Dialect.Sqlite
      { select with projection = []; group_by = [ bad_expression ] });
  assert (
    Lower.select_has_unsupported_having
      ~dialect:Dialect.Sqlite
      { select with
        projection = []
      ; group_by = [ column 0 ]
      ; having = Some (A.Exists nested_select)
      });
  let bad_assignment = { assignment with A.value = A.Expression bad_expression } in
  assert (Lower.assignment_has_unsupported_having ~dialect:Dialect.Sqlite bad_assignment);
  assert (
    not
      (Lower.assignment_has_unsupported_having
         ~dialect:Dialect.Sqlite
         { assignment with A.value = A.Default }));
  assert (
    Lower.command_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (command A.Insert [ bad_assignment ]));
  assert (
    Lower.command_has_unsupported_having
      ~dialect:Dialect.Sqlite
      (command A.Update [ bad_assignment ]));
  assert (
    Lower.command_has_unsupported_having
      ~dialect:Dialect.Sqlite
      { (command A.Insert [ assignment ]) with
        conflict =
          Some
            (A.Do_update
               { target = [ conflict_column (Identifier.of_string_exn "id") ]
               ; excluded_source_id = 1
               ; where_ = None
               ; assignments = [ bad_assignment ]
               })
      });
  assert (
    Lower.command_has_unsupported_having
      ~dialect:Dialect.Sqlite
      { (command A.Update [ assignment ]) with where_ = Some (A.Exists nested_select) });
  (match Lower.command ~dialect:Dialect.Sqlite (command A.Update [ bad_assignment ]) with
   | Error (Compile_error.Unsupported_operation { dialect = Dialect.Sqlite; _ }) -> ()
   | _ -> failwith "UPDATE did not reject a nested unsupported HAVING");
  (match
     Lower.command
       ~dialect:Dialect.Sqlite
       { (command A.Insert [ assignment ]) with
         conflict =
           Some
             (A.Do_update
                { target = [ conflict_column (Identifier.of_string_exn "id") ]
                ; excluded_source_id = 1
                ; where_ = None
                ; assignments = [ { assignment with A.value = A.Default } ]
                })
       }
   with
   | Error (Compile_error.Unsupported_operation { dialect = Dialect.Sqlite; _ }) -> ()
   | _ -> failwith "SQLite accepted DEFAULT in an UPSERT assignment");
  (match
     Lower.result_query
       ~dialect:Dialect.Sqlite
       (A.Returning
          { command = command A.Insert [ assignment ]; projection = [ bad_expression ] })
   with
   | Error (Compile_error.Unsupported_operation { dialect = Dialect.Sqlite; _ }) -> ()
   | _ -> failwith "RETURNING did not reject a nested unsupported HAVING");
  assert (
    not (Lower.select_has_unsupported_having ~dialect:Dialect.Postgresql nested_select));
  assert (Aggregate_scope.at_most_one { select with limit = Some (A.Literal 0) });
  assert (Aggregate_scope.at_most_one { select with limit = Some (A.Literal 1) });
  assert (not (Aggregate_scope.at_most_one { select with limit = Some (A.Literal 2) }));
  assert (
    Aggregate_scope.at_most_one { select with projection = [ A.Aggregate A.Count_all ] });
  assert (Aggregate_scope.at_most_one { select with projection = [ local_aggregate ] });
  assert (
    Aggregate_scope.at_most_one
      { select with
        joins = [ { A.kind = A.Inner; source = source 1; on = A.True } ]
      ; projection = [ A.Aggregate (A.Count_distinct (column 1)) ]
      });
  assert (
    not
      (Aggregate_scope.at_most_one
         { select with projection = [ A.Aggregate (A.Count (column 1)) ] }));
  assert (
    Aggregate_scope.at_most_one
      { select with projection = [ A.Aggregate (A.Count parameter) ] });
  assert (
    Aggregate_scope.at_most_one
      { select with projection = [ A.Aggregate (A.Count_distinct parameter) ] })
;;
