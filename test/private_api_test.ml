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
  ; locking = None
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
  let assignments, insert_input =
    match kind with
    | A.Insert -> [], Some (A.Rows [ assignments ])
    | A.Update -> assignments, None
    | A.Delete -> [], None
  in
  { ctes = []
  ; kind
  ; source = source 0
  ; assignments
  ; insert_input
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

let%test_module "private query inspection" =
  (module struct
    let table : unit Table.t = Table.v_exn "items"
    let id = Column.v_exn table "id" Db_type.int
    let builder = Query.(from table |> where (fun row -> Expr.column row id =$ 7))
    let ast = Query.(ast builder)

    let original =
      Query.(builder |> select (fun row -> Projection.expr (Expr.column row id)))
    ;;

    let projection = Result_query.projection original
    let rebuilt_ast = { ast with A.projection = Projection.expressions projection }
    let rebuilt = Result_query.create_select (A.Simple rebuilt_ast) projection
    let compile query = Compiler.compile ~dialect:Dialect.sqlite query |> ok_exn
    let compiled_original = compile original
    let compiled_rebuilt = compile rebuilt

    let%test "reconstructed query preserves shape" =
      Shape.equal
        (Compiled_query.shape compiled_original)
        (Compiled_query.shape compiled_rebuilt)
    ;;

    let%test "compiled query formatter matches SQL" =
      String.equal
        (Stdlib.Format.asprintf "%a" Compiled_query.pp compiled_original)
        (Compiled_query.sql compiled_original)
    ;;

    let%test "projection keeps source identity" =
      match Projection.expressions projection with
      | [ A.Column { source_id; _ } ] -> Int.(source_id = rebuilt_ast.source.source_id)
      | _ -> false
    ;;

    let%expect_test "reconstructed query SQL" =
      Stdlib.print_endline (Compiled_query.sql compiled_rebuilt);
      [%expect
        {|
        SELECT
          t0."id"
        FROM "items" AS t0
        WHERE
          (t0."id" = ?1)
        |}]
    ;;

    let%test "nullable table reference keeps source identity" =
      let reference = Table_ref.create table in
      let nullable = Nullable_table_ref.of_table_ref reference in
      Int.(Table_ref.source_id reference = Nullable_table_ref.source_id nullable)
    ;;
  end)
;;

let%test_module "condition normalization" =
  (module struct
    let atom = A.Is_null (column 0)

    let check input expected =
      let normalized = Normalizer.normalize_condition input in
      equal_condition normalized expected
      && equal_condition (Normalizer.normalize_condition normalized) normalized
    ;;

    let%test "empty conjunction becomes TRUE" = check (A.And []) A.True
    let%test "empty disjunction becomes FALSE" = check (A.Or []) A.False

    let%test "TRUE identities flatten conjunctions" =
      check (A.And [ A.True; atom; A.And [ A.True ] ]) atom
    ;;

    let%test "FALSE identities flatten disjunctions" =
      check (A.Or [ A.False; atom; A.Or [ A.False ] ]) atom
    ;;

    let%test "FALSE absorbs conjunctions" = check (A.And [ atom; A.False ]) A.False
    let%test "TRUE absorbs disjunctions" = check (A.Or [ atom; A.True ]) A.True
    let%test "NOT TRUE becomes FALSE" = check (A.Not A.True) A.False
    let%test "NOT FALSE becomes TRUE" = check (A.Not A.False) A.True
    let%test "double negation is removed" = check (A.Not (A.Not atom)) atom
    let%test "atomic negation is retained" = check (A.Not atom) (A.Not atom)

    let%test "nested conjunctions flatten" =
      check (A.And [ atom; A.And [ atom; atom ] ]) (A.And [ atom; atom; atom ])
    ;;

    let%test "nested disjunctions flatten" =
      check (A.Or [ atom; A.Or [ atom; atom ] ]) (A.Or [ atom; atom; atom ])
    ;;
  end)
;;

let%test_module "SELECT validator diagnostics" =
  (module struct
    let validate query =
      Validator.result_query (A.Select (A.Simple query)) |> print_validation
    ;;

    let%expect_test "empty projection" =
      validate { select with projection = [] };
      [%expect {| SELECT projection must contain at least one expression |}]
    ;;

    let%expect_test "negative limit" =
      validate { select with limit = Some (A.Limit (A.Literal (-1))) };
      [%expect {| LIMIT must be non-negative, got -1 |}]
    ;;

    let%expect_test "negative offset" =
      validate { select with offset = Some (A.Literal (-2)) };
      [%expect {| OFFSET must be non-negative, got -2 |}]
    ;;

    let%expect_test "invalid projection source" =
      validate { select with projection = [ column 99 ] };
      [%expect {| expression references source #99, but the visible sources are 0 |}]
    ;;

    let%expect_test "invalid order source" =
      validate { select with order_by = [ { expr = column 99; direction = A.Desc } ] };
      [%expect {| expression references source #99, but the visible sources are 0 |}]
    ;;

    let first : A.join =
      { kind = A.Inner; source = source 1; on = A.Compare (A.Eq, column 0, column 1) }
    ;;

    let second : A.join =
      { kind = A.Left; source = source 2; on = A.Compare (A.Eq, column 1, column 2) }
    ;;

    let%test_unit "valid multi-join scope" =
      Validator.result_query
        (A.Select
           (A.Simple { select with joins = [ first; second ]; projection = [ column 2 ] }))
      |> ok_exn
    ;;

    let%expect_test "invalid JOIN scope" =
      validate
        { select with joins = [ { first with on = A.Is_not_null (column 2) }; second ] };
      [%expect {| expression references source #2, but the visible sources are 0, 1 |}]
    ;;
  end)
;;

let%test_module "FETCH WITH TIES cardinality proofs" =
  (module struct
    let fetch_with_ties =
      { select with
        order_by = [ { expr = column 0; direction = A.Asc } ]
      ; limit = Some (A.Fetch_with_ties (A.Literal 1))
      }
    ;;

    let%test "does not prove at most one row" =
      not (Aggregate_scope.at_most_one fetch_with_ties)
    ;;

    let aggregate =
      { fetch_with_ties with
        projection = [ A.Aggregate A.Count_all ]
      ; order_by = [ { expr = A.Aggregate A.Count_all; direction = A.Asc } ]
      }
    ;;

    let%test "positive count preserves ungrouped aggregate exactly-one proof" =
      Aggregate_scope.exactly_one aggregate
    ;;

    let%test_unit "SQLite lowering rejects the PostgreSQL-only clause" =
      match
        Lower.result_query ~dialect:Dialect.Sqlite (A.Select (A.Simple fetch_with_ties))
      with
      | Error
          (Compile_error.Unsupported_operation
             { operation = "FETCH FIRST WITH TIES"; dialect = Dialect.Sqlite }) -> ()
      | Error error -> failwith (Compile_error.to_string error)
      | Ok _ -> failwith "SQLite lowering accepted FETCH WITH TIES"
    ;;
  end)
;;

let%test_module "FOR UPDATE compiler invariants" =
  (module struct
    let table : unit Table.t = Table.v_exn "lock_items"
    let id = Column.v_exn table "id" Db_type.int

    let make ?(skip_locked = false) () =
      Query.(
        from table
        |> for_update ~of_:(fun row -> [ lock_target row ]) ~skip_locked
        |> select (fun row -> Projection.expr (Expr.column row id)))
    ;;

    let%test "shape excludes generative lock target IDs" =
      let first = Compiler.compile ~dialect:Dialect.postgresql (make ()) |> ok_exn in
      let second = Compiler.compile ~dialect:Dialect.postgresql (make ()) |> ok_exn in
      Shape.equal (Compiled_query.shape first) (Compiled_query.shape second)
    ;;

    let%test "SKIP LOCKED changes shape" =
      let plain = Compiler.compile ~dialect:Dialect.postgresql (make ()) |> ok_exn in
      let skip =
        Compiler.compile ~dialect:Dialect.postgresql (make ~skip_locked:true ()) |> ok_exn
      in
      not (Shape.equal (Compiled_query.shape plain) (Compiled_query.shape skip))
    ;;

    let%test_unit "SQLite rejects the locking clause" =
      match Compiler.compile ~dialect:Dialect.sqlite (make ()) with
      | Error
          (Compile_error.Unsupported_operation
             { operation = "FOR UPDATE"; dialect = Dialect.Sqlite }) -> ()
      | Error error -> failwith (Compile_error.to_string error)
      | Ok _ -> failwith "SQLite accepted FOR UPDATE"
    ;;
  end)
;;

let%test_module "DML validator diagnostics" =
  (module struct
    let validate command = Validator.command command |> print_validation

    let%expect_test "empty INSERT assignments" =
      validate (command A.Insert []);
      [%expect {| INSERT must assign at least one column |}]
    ;;

    let%expect_test "missing INSERT row source" =
      validate { (command A.Insert [ assignment ]) with insert_input = None };
      [%expect {| INSERT has no row source |}]
    ;;

    let%expect_test "command target must be a base table" =
      validate { (command A.Delete []) with source = { source_id = 0; kind = A.Cte 12 } };
      [%expect {| command target must be a base table |}]
    ;;

    let%expect_test "mixed INSERT row sources" =
      validate
        { (command A.Insert [ assignment ]) with insert_input = Some A.Mixed_sources };
      [%expect {| INSERT cannot combine VALUES and SELECT sources |}]
    ;;

    let%expect_test "INSERT SELECT with no target columns" =
      validate
        { (command A.Insert [ assignment ]) with
          insert_input =
            Some
              (A.Select_rows
                 { columns = []
                 ; query = A.Simple select
                 ; result_types = [ Db_type.Pack Db_type.int ]
                 })
        };
      [%expect {| INSERT must assign at least one column |}]
    ;;

    let%expect_test "empty UPDATE assignments" =
      validate (command A.Update []);
      [%expect {| UPDATE must assign at least one column |}]
    ;;

    let%expect_test "duplicate assignments" =
      validate (command A.Update [ assignment; assignment ]);
      [%expect {| column id is assigned more than once |}]
    ;;

    let%expect_test "foreign assignment source" =
      validate (command A.Update [ { assignment with source_id = 99 } ]);
      [%expect {| assignment belongs to source #99, but the command targets source #0 |}]
    ;;

    let%expect_test "foreign assignment expression" =
      validate (command A.Update [ { assignment with value = A.Expression (column 99) } ]);
      [%expect {| expression references source #99, but the visible sources are 0 |}]
    ;;

    let%expect_test "foreign DELETE predicate" =
      validate
        { (command A.Delete []) with where_ = Some (A.Not (A.Is_null (column 99))) };
      [%expect {| expression references source #99, but the visible sources are 0 |}]
    ;;

    let insert = command A.Insert [ assignment ]

    let%expect_test "empty RETURNING projection" =
      Validator.result_query (A.Returning { command = insert; projection = [] })
      |> print_validation;
      [%expect {| SELECT projection must contain at least one expression |}]
    ;;

    let%expect_test "foreign RETURNING projection" =
      Validator.result_query
        (A.Returning { command = insert; projection = [ column 99 ] })
      |> print_validation;
      [%expect {| expression references source #99, but the visible sources are 0 |}]
    ;;

    let%test_unit "valid INSERT" = Validator.command insert |> ok_exn

    let%test "compiled command formatter matches SQL" =
      let template, parameters = Renderer.command ~dialect:Dialect.Postgresql insert in
      let compiled =
        Compiled_command.create
          ~dialect:Dialect.Postgresql
          ~template
          ~parameters:
            (List.filter_map parameters ~f:(function
               | A.Value value -> Some value
               | A.Slot _ -> None))
          ~shape:(Shape.create "insert")
      in
      String.equal
        (Stdlib.Format.asprintf "%a" Compiled_command.pp compiled)
        (Compiled_command.sql compiled)
    ;;
  end)
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

let%test_module "unavailable CTE diagnostics" =
  (module struct
    let cte_id = 701
    let nested_source = cte_source ~cte_id 1

    let nested =
      { select with
        source = nested_source
      ; projection = [ column nested_source.source_id ]
      ; limit = Some (A.Limit (A.Literal 1))
      }
    ;;

    let expect_unknown = function
      | Error (Compile_error.Unknown_cte actual) -> assert (Int.(actual = cte_id))
      | Error error ->
        failwith ("expected Unknown_cte, got " ^ Compile_error.to_string error)
      | Ok () -> failwith "unknown CTE was accepted"
    ;;

    let%test_unit "scalar subquery cannot access an unavailable CTE" =
      let scalar =
        A.Select (A.Simple { select with projection = [ A.Scalar_subquery nested ] })
      in
      expect_unknown (Validator.result_query scalar)
    ;;

    let%test_unit "EXISTS subquery cannot access an unavailable CTE" =
      let exists = A.Select (A.Simple { select with where_ = Some (A.Exists nested) }) in
      expect_unknown (Validator.result_query exists)
    ;;
  end)
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

let%test_unit "validator rejects a recursive anchor with the wrong CTE type" =
  let cte_id = 704 in
  let cte = recursive_cte ~cte_id ~step:(int_relation (cte_source ~cte_id 2)) in
  let cte =
    { cte with
      body =
        A.Recursive_body
          { union = A.Recursive_union_all
          ; anchor = text_relation (source 1)
          ; step = int_relation (cte_source ~cte_id 2)
          }
    }
  in
  match Validator.result_query (query_with_cte cte) with
  | Error (Compile_error.Mismatched_relation_projection _) -> ()
  | Error error ->
    failwith
      ("expected Mismatched_relation_projection, got " ^ Compile_error.to_string error)
  | Ok () -> failwith "recursive CTE accepted an anchor with the wrong type"
;;

let%test_module "recursive CTE self-reference validation" =
  (module struct
    let cte_id = 703
    let direct_self = cte_source ~cte_id 2

    let direct_step source =
      { (int_relation direct_self) with
        query =
          A.Simple
            { select with
              source = direct_self
            ; joins = [ { kind = A.Inner; source; on = A.True } ]
            ; projection = [ column direct_self.source_id ]
            }
      }
    ;;

    let expect_invalid = function
      | Error (Compile_error.Invalid_recursive_reference actual) ->
        assert (Int.(actual = cte_id))
      | Error error ->
        failwith
          ("expected Invalid_recursive_reference, got " ^ Compile_error.to_string error)
      | Ok () -> failwith "invalid recursive CTE was accepted"
    ;;

    let%test_unit "rejects an extra direct self-reference" =
      let extra_self = cte_source ~cte_id 3 in
      let step = direct_step extra_self in
      expect_invalid
        (Validator.result_query (query_with_cte (recursive_cte ~cte_id ~step)))
    ;;

    let%test_unit "rejects a self-reference inside a derived relation" =
      let nested_self = cte_source ~cte_id 4 in
      let nested_relation = int_relation nested_self in
      let nested_source : A.source =
        { source_id = 3; kind = A.Derived nested_relation }
      in
      let step = direct_step nested_source in
      expect_invalid
        (Validator.result_query (query_with_cte (recursive_cte ~cte_id ~step)))
    ;;
  end)
;;

let%test_module "private conflict validator diagnostics" =
  (module struct
    let id = Identifier.of_string_exn "id"
    let insert = command A.Insert [ assignment ]

    let validate conflict =
      Validator.command { insert with conflict = Some conflict } |> print_validation
    ;;

    let%expect_test "empty DO NOTHING target" =
      validate (A.Do_nothing (Some []));
      [%expect {| ON CONFLICT target must contain at least one column |}]
    ;;

    let%expect_test "empty DO UPDATE target" =
      validate
        (A.Do_update
           { target = []
           ; excluded_source_id = 1
           ; where_ = None
           ; assignments = [ assignment ]
           });
      [%expect {| ON CONFLICT target must contain at least one column |}]
    ;;

    let%expect_test "duplicate conflict target" =
      validate
        (A.Do_update
           { target = [ conflict_column id; conflict_column id ]
           ; excluded_source_id = 1
           ; where_ = None
           ; assignments = [ assignment ]
           });
      [%expect {| ON CONFLICT target contains column id more than once |}]
    ;;

    let%expect_test "foreign conflict target" =
      validate (A.Do_nothing (Some [ conflict_column ~source_id:99 id ]));
      [%expect {| ON CONFLICT target column belongs to source #99, expected source #0 |}]
    ;;

    let%expect_test "duplicate conflict assignments" =
      validate
        (A.Do_update
           { target = [ conflict_column id ]
           ; excluded_source_id = 1
           ; where_ = None
           ; assignments = [ assignment; assignment ]
           });
      [%expect {| column id is assigned more than once |}]
    ;;
  end)
;;

let%test "private commands reach compiler validation" =
  let invalid = command A.Update [] |> Command.create in
  match Compiler.compile_command ~dialect:Dialect.sqlite invalid with
  | Error (Compile_error.Empty_assignments `Update) -> true
  | _ -> false
;;

let%test_module "private UPSERT DEFAULT capability" =
  (module struct
    let command =
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
      |> Command.create
    ;;

    let%test_unit "PostgreSQL accepts DEFAULT in UPSERT assignments" =
      ignore (Compiler.compile_command ~dialect:Dialect.postgresql command |> ok_exn)
    ;;

    let%test_unit "SQLite rejects DEFAULT in UPSERT assignments" =
      match Compiler.compile_command ~dialect:Dialect.sqlite command with
      | Error
          (Compile_error.Unsupported_operation { operation; dialect = Dialect.Sqlite }) ->
        assert (String.equal operation "ON CONFLICT DO UPDATE SET DEFAULT")
      | _ -> failwith "SQLite accepted an UPSERT DEFAULT assignment"
    ;;
  end)
;;

let%test_module "opaque public constructors" =
  (module struct
    let expression : (int, Dialect.portable) Expr.t =
      Expr.create (A.Param (A.Value (Db_type.Value (Db_type.int, 42)))) Db_type.int
    ;;

    let condition : Dialect.portable Condition.t =
      Condition.create (A.Is_not_null (Expr.node expression))
    ;;

    let template : Template.t =
      Template.of_parts [ Template.Text "SELECT "; Template.Param 0 ]
    ;;

    let projection = Projection.expr expression
    let shape : Shape.t = Shape.create (Template.shape_string template)

    let compiled : int Compiled_query.t =
      Compiled_query.create
        ~dialect:Dialect.Sqlite
        ~template
        ~parameters:[ Db_type.Value (Db_type.int, 42) ]
        ~projection:(Projection.erase projection)
        ~shape
    ;;

    let%test "condition constructor preserves its opaque representation" =
      match Condition.node condition with
      | A.Is_not_null (A.Param _) -> true
      | _ -> false
    ;;

    let%test "compiled query preserves its supplied shape" =
      Shape.equal shape (Compiled_query.shape compiled)
    ;;

    let%expect_test "compiled query SQL" =
      Stdlib.print_endline (Compiled_query.sql compiled);
      [%expect {| SELECT ?1 |}]
    ;;
  end)
;;

let%test_module "template layout identity" =
  (module struct
    let compact = Template.of_parts [ Template.Text "SELECT "; Template.Param 0 ]

    let formatted =
      Template.of_parts
        [ Template.Text "SELECT"
        ; Template.Nest (Template.of_parts [ Template.Break " "; Template.Param 0 ])
        ]
    ;;

    let%test "template whitespace does not affect query shape" =
      String.equal (Template.shape_string compact) (Template.shape_string formatted)
    ;;

    let%test "template layout affects rendered SQL" =
      not
        (String.equal
           (Template.to_sql ~dialect:Dialect.Sqlite compact)
           (Template.to_sql ~dialect:Dialect.Sqlite formatted))
    ;;
  end)
;;

let%test_module "lowered DML rendering" =
  (module struct
    let ast =
      A.Returning
        { command = command A.Insert [ assignment ]
        ; projection =
            [ column 0; A.Param (A.Value (Db_type.Value (Db_type.text, "returned"))) ]
        }
      |> Normalizer.result_query
    ;;

    let render dialect =
      Validator.result_query ast |> ok_exn;
      let lowered = Lower.result_query ~dialect ast |> ok_exn in
      let template, parameters = Renderer.result_query ~dialect lowered in
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
    ;;

    let%expect_test "PostgreSQL" =
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
        |}]
    ;;

    let%expect_test "SQLite" =
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
  end)
;;

let%test_module "renderer totality for malformed private AST" =
  (module struct
    let render query =
      let template, _ = Renderer.result_query ~dialect:Dialect.Sqlite query in
      Template.to_sql ~dialect:Dialect.Sqlite template
    ;;

    let%test_unit "renders TRUE predicates" =
      assert (
        String.equal
          (render (A.Select (A.Simple { select with where_ = Some A.True })))
          "SELECT\n  t0.\"id\"\nFROM \"items\" AS t0\nWHERE\n  TRUE")
    ;;

    let%test_unit "renders empty conjunctions" =
      assert (
        String.equal
          (render (A.Select (A.Simple { select with where_ = Some (A.And []) })))
          "SELECT\n  t0.\"id\"\nFROM \"items\" AS t0\nWHERE\n  ()")
    ;;

    let%test_unit "renders empty RETURNING projections" =
      ignore
        (render
           (A.Returning { command = command A.Insert [ assignment ]; projection = [] }))
    ;;

    let%test_unit "renders empty UPDATE assignments" =
      ignore (Renderer.command ~dialect:Dialect.Postgresql (command A.Update []))
    ;;

    let%test_unit "renders empty INSERT assignments" =
      ignore (Renderer.command ~dialect:Dialect.Postgresql (command A.Insert []))
    ;;

    let%test_unit "renders empty multiset aggregates" =
      ignore
        (Renderer.render_expr
           ~aliases:[]
           (A.Aggregate
              (A.Multiset_agg
                 { fields = []; field_types = []; filter = None; order_by = [] }))
           Renderer.initial_state)
    ;;

    let%test_unit "renders an empty CTE list" =
      ignore (Renderer.render_ctes [] Renderer.initial_state)
    ;;

    let%test_unit "renders empty INSERT rows with an invalid alias" =
      ignore
        (Renderer.render_insert_rows
           ~aliases:[ 0, "" ]
           ~columns:[]
           []
           Renderer.initial_state)
    ;;
  end)
;;

let%test_module "private helper boundary cases" =
  (module struct
    let rendered_sources =
      let sources =
        Renderer.render_from_sources
          ~aliases:[ 0, "t0"; 1, "t1" ]
          [ source 0; source 1 ]
          Renderer.initial_state
        |> fst
      in
      Template.of_parts [ Template.Nest sources ]
      |> Template.to_sql ~dialect:Dialect.Sqlite
    ;;

    let concat = A.Concat (column 0, column 0)

    let left : Validator.aggregate_analysis =
      { has_aggregate = false; nested_aggregate = false; grouped = true }
    ;;

    let right : Validator.aggregate_analysis =
      { has_aggregate = true; nested_aggregate = true; grouped = true }
    ;;

    let nested_count = A.Aggregate (A.Count (A.Aggregate (A.Count (column 0))))

    let%test_unit "lowers TRUE conditions" =
      match Lower.condition ~dialect:Dialect.Sqlite A.True with
      | A.True -> ()
      | _ -> failwith "lowering changed a true condition"
    ;;

    let%test "normalizes optional TRUE conditions away" =
      Option.is_none (Normalizer.optional_condition (Some A.True))
    ;;

    let%test_unit "renders an empty ORDER BY list" =
      ignore (Renderer.render_order_by ~aliases:[ 0, "t0" ] [] Renderer.initial_state)
    ;;

    let%test "renders a single condition list" =
      let single, _ =
        Renderer.render_condition_list
          ~aliases:[ 0, "t0" ]
          ~operator:"AND"
          [ A.True ]
          Renderer.initial_state
      in
      String.equal (Template.to_sql ~dialect:Dialect.Sqlite single) "(TRUE)"
    ;;

    let%test "renders an empty condition list" =
      let conditions, _ =
        Renderer.render_conditions
          ~aliases:[ 0, "t0" ]
          ~operator:"AND"
          []
          Renderer.initial_state
      in
      String.is_empty (Template.to_sql ~dialect:Dialect.Sqlite conditions)
    ;;

    let%test "renders no FROM sources" =
      let template, _ =
        Renderer.render_from_sources ~aliases:[] [] Renderer.initial_state
      in
      String.is_empty (Template.to_sql ~dialect:Dialect.Sqlite template)
    ;;

    let%test "renders multiple FROM sources" =
      String.equal rendered_sources "\"items\" AS t0,\n  \"items\" AS t1"
    ;;

    let%test "does not equate a column with a parameter" =
      not
        (Validator.same_column
           (column 0)
           (A.Param (A.Value (Db_type.Value (Db_type.int, 0)))))
    ;;

    let arithmetic = A.Arithmetic (A.Add, column 0, column 0)

    let%test "compares arithmetic group expressions" =
      Validator.same_group_expression arithmetic arithmetic
    ;;

    let%test "compares arithmetic operators with themselves" =
      List.for_all [ A.Add; A.Subtract; A.Multiply; A.Divide ] ~f:(fun operator ->
        Validator.same_arithmetic operator operator)
    ;;

    let%test "distinguishes different arithmetic operators" =
      not (Validator.same_arithmetic A.Add A.Subtract)
    ;;

    let%test "compares string functions with themselves" =
      List.for_all [ A.Lower; A.Upper; A.Length ] ~f:(fun function_ ->
        Validator.same_string_function function_ function_)
    ;;

    let%test "distinguishes different string functions" =
      not (Validator.same_string_function A.Lower A.Upper)
    ;;

    let%test "does not equate unsupported SQLite string functions" =
      not (Validator.same_string_function A.Sqlite_length A.Sqlite_length)
    ;;

    let%test "compares concatenated group expressions" =
      Validator.same_group_expression concat concat
    ;;

    let%test "combines aggregate analysis in either order" =
      (Validator.combine left right).nested_aggregate
      && (Validator.combine right left).nested_aggregate
    ;;

    let validate_subquery ~outer_visible:_ ~allow_empty:_ _ = Ok ()

    let%test_unit "validates a TRUE condition without sources" =
      Validator.validate_condition ~validate_subquery ~visible:[] A.True |> ok_exn
    ;;

    let%test_unit "analyzes a TRUE condition" =
      ignore (Validator.analyze_condition ~groups:[] ~inside_aggregate:false A.True)
    ;;

    let%test "detects nested aggregate expressions" =
      (Validator.analyze_expression ~groups:[] ~inside_aggregate:false nested_count)
        .nested_aggregate
    ;;

    let%test "aggregate source traversal visits aggregate arguments" =
      List.is_empty
        (Aggregate_scope.expression_sources
           (A.Aggregate (A.Count (A.Aggregate A.Count_all))))
    ;;

    let%test "rejects INSERT with no rows" =
      match
        Validator.command { (command A.Insert []) with insert_input = Some (A.Rows []) }
      with
      | Error (Compile_error.Empty_assignments `Insert) -> true
      | _ -> false
    ;;
  end)
;;

let%test_module "lowering capability traversal" =
  (module struct
    let parameter = A.Param (A.Value (Db_type.Value (Db_type.int, 1)))
    let nested_select = { select with having = Some A.True }

    let expression =
      A.Case
        ( [ ( A.Compare (A.Eq, column 0, parameter)
            , A.Arithmetic (A.Add, A.String_function (A.Length, column 0), parameter) )
          ]
        , A.Concat (A.Aggregate (A.Count_distinct (column 0)), A.Scalar_subquery select)
        )
    ;;

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
    ;;

    let complete_select =
      { select with
        joins = [ { A.kind = A.Inner; source = source 1; on = condition } ]
      ; projection = [ expression ]
      ; where_ = Some condition
      ; group_by = [ expression ]
      ; having = Some condition
      ; order_by = [ { A.expr = expression; direction = A.Asc } ]
      }
    ;;

    let bad_expression = A.Scalar_subquery nested_select

    let bad_multiset_aggregate =
      A.Aggregate
        (A.Multiset_agg
           { fields = []
           ; field_types = []
           ; filter = Some (A.Exists nested_select)
           ; order_by = []
           })
    ;;

    let bad_ordered_multiset =
      A.Aggregate
        (A.Multiset_agg
           { fields = []
           ; field_types = []
           ; filter = None
           ; order_by = [ { A.expr = bad_expression; direction = A.Desc } ]
           })
    ;;

    let bad_multiset_subquery =
      A.Multiset_subquery
        { query = A.Simple nested_select; field_types = [ Db_type.Pack Db_type.int ] }
    ;;

    let bad_assignment = { assignment with A.value = A.Expression bad_expression }

    let unsupported_set operator =
      A.Select
        (A.Compound
           { ctes = []
           ; operator
           ; left = A.Simple select
           ; right = A.Simple select
           ; left_types = [ Db_type.Pack Db_type.int ]
           ; right_types = [ Db_type.Pack Db_type.int ]
           ; order_by = []
           })
    ;;

    let is_sqlite_unsupported = function
      | Error (Compile_error.Unsupported_operation { dialect = Dialect.Sqlite; _ }) ->
        true
      | Error _ | Ok _ -> false
    ;;

    let%test "lowering preserves the mixed-source marker until validation" =
      let insert =
        { (command A.Insert [ assignment ]) with insert_input = Some A.Mixed_sources }
      in
      match Lower.command ~dialect:Dialect.Postgresql insert with
      | Ok { A.insert_input = Some A.Mixed_sources; _ } -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "SQLite capability scan tolerates the mixed-source marker" =
      let insert =
        { (command A.Insert [ assignment ]) with insert_input = Some A.Mixed_sources }
      in
      match Lower.command ~dialect:Dialect.Sqlite insert with
      | Ok { A.insert_input = Some A.Mixed_sources; _ } -> true
      | Ok _ | Error _ -> false
    ;;

    let%test "supported SQLite SELECT has no unsupported HAVING" =
      not (Lower.select_has_unsupported_having ~dialect:Dialect.Sqlite complete_select)
    ;;

    let%test "scalar subquery traversal finds unsupported HAVING" =
      Lower.expression_has_unsupported_having ~dialect:Dialect.Sqlite bad_expression
    ;;

    let%test "multiset aggregate filter traversal finds unsupported HAVING" =
      Lower.expression_has_unsupported_having
        ~dialect:Dialect.Sqlite
        bad_multiset_aggregate
    ;;

    let%test "ordered multiset traversal finds unsupported HAVING" =
      Lower.expression_has_unsupported_having ~dialect:Dialect.Sqlite bad_ordered_multiset
    ;;

    let%test "multiset subquery traversal finds unsupported HAVING" =
      Lower.expression_has_unsupported_having
        ~dialect:Dialect.Sqlite
        bad_multiset_subquery
    ;;

    let%test "arithmetic expression traversal finds unsupported HAVING" =
      Lower.expression_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.Arithmetic (A.Add, bad_expression, column 0))
    ;;

    let%test "CASE result traversal finds unsupported HAVING" =
      Lower.expression_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.Case ([ A.True, column 0 ], bad_expression))
    ;;

    let%test "CASE condition traversal finds unsupported HAVING" =
      Lower.expression_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.Case ([ A.Exists nested_select, column 0 ], column 0))
    ;;

    let%test "EXISTS traversal finds unsupported HAVING" =
      Lower.condition_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.Exists nested_select)
    ;;

    let%test "comparison traversal finds unsupported HAVING" =
      Lower.condition_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.Compare (A.Eq, bad_expression, column 0))
    ;;

    let%test "IN list traversal finds unsupported HAVING" =
      Lower.condition_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.In (bad_expression, [ column 0 ]))
    ;;

    let%test "IN subquery traverses the subquery" =
      Lower.condition_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.In_subquery (parameter, nested_select))
    ;;

    let%test "IN subquery traverses its expression" =
      Lower.condition_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (A.In_subquery (bad_expression, select))
    ;;

    let%test "projection traversal finds unsupported HAVING" =
      Lower.select_has_unsupported_having
        ~dialect:Dialect.Sqlite
        { select with projection = [ bad_expression ]; group_by = [ column 0 ] }
    ;;

    let%test "JOIN predicate traversal finds unsupported HAVING" =
      Lower.select_has_unsupported_having
        ~dialect:Dialect.Sqlite
        { select with
          joins = [ { A.kind = A.Inner; source = source 1; on = A.Exists nested_select } ]
        ; projection = []
        }
    ;;

    let%test "WHERE traversal finds unsupported HAVING" =
      Lower.select_has_unsupported_having
        ~dialect:Dialect.Sqlite
        { select with projection = []; where_ = Some (A.Exists nested_select) }
    ;;

    let%test "GROUP BY traversal finds unsupported HAVING" =
      Lower.select_has_unsupported_having
        ~dialect:Dialect.Sqlite
        { select with projection = []; group_by = [ bad_expression ] }
    ;;

    let%test "HAVING traversal finds unsupported HAVING" =
      Lower.select_has_unsupported_having
        ~dialect:Dialect.Sqlite
        { select with
          projection = []
        ; group_by = [ column 0 ]
        ; having = Some (A.Exists nested_select)
        }
    ;;

    let%test "assignment traversal finds unsupported HAVING" =
      Lower.assignment_has_unsupported_having ~dialect:Dialect.Sqlite bad_assignment
    ;;

    let%test "DEFAULT assignment does not contain unsupported HAVING" =
      not
        (Lower.assignment_has_unsupported_having
           ~dialect:Dialect.Sqlite
           { assignment with A.value = A.Default })
    ;;

    let%test_unit "SQLite lowering rejects direct INSERT and UPDATE DEFAULT" =
      let default_assignment = { assignment with A.value = A.Default } in
      assert (
        is_sqlite_unsupported
          (Lower.command
             ~dialect:Dialect.Sqlite
             (command A.Insert [ default_assignment ])));
      assert (
        is_sqlite_unsupported
          (Lower.command
             ~dialect:Dialect.Sqlite
             (command A.Update [ default_assignment ])))
    ;;

    let%test "SQLite lowering rejects PostgreSQL numeric aggregates" =
      let numeric_aggregate =
        A.Aggregate
          (A.Sum_int64
             (A.Column
                { source_id = 0
                ; name = Identifier.of_string_exn "id"
                ; db_type = Db_type.Pack Db_type.int64
                }))
      in
      is_sqlite_unsupported
        (Lower.result_query
           ~dialect:Dialect.Sqlite
           (A.Select (A.Simple { select with projection = [ numeric_aggregate ] })))
    ;;

    let%test "SQLite command lowering rejects unsupported numeric expressions" =
      let numeric_aggregate =
        A.Aggregate
          (A.Sum_int64
             (A.Column
                { source_id = 0
                ; name = Identifier.of_string_exn "id"
                ; db_type = Db_type.Pack Db_type.int64
                }))
      in
      is_sqlite_unsupported
        (Lower.command
           ~dialect:Dialect.Sqlite
           (command
              A.Update
              [ { assignment with A.value = A.Expression numeric_aggregate } ]))
    ;;

    let%test "SQLite lowering rejects ungrouped HAVING on SELECT" =
      is_sqlite_unsupported
        (Lower.result_query
           ~dialect:Dialect.Sqlite
           (A.Select (A.Simple { select with having = Some A.True })))
    ;;

    let%test "command CTE traversal checks nested assignments" =
      let cte : A.cte =
        { cte_id = 7
        ; columns = []
        ; column_types = []
        ; result_types = []
        ; materialization = None
        ; body = A.Command_body (command A.Update [ bad_assignment ])
        }
      in
      Lower.select_has_unsupported_having
        ~dialect:Dialect.Sqlite
        { select with ctes = [ cte ]; projection = [] }
    ;;

    let%test "INSERT assignment traversal finds unsupported HAVING" =
      Lower.command_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (command A.Insert [ bad_assignment ])
    ;;

    let%test "UPDATE assignment traversal finds unsupported HAVING" =
      Lower.command_has_unsupported_having
        ~dialect:Dialect.Sqlite
        (command A.Update [ bad_assignment ])
    ;;

    let%test "UPSERT assignment traversal finds unsupported HAVING" =
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
        }
    ;;

    let%test "UPDATE predicate traversal finds unsupported HAVING" =
      Lower.command_has_unsupported_having
        ~dialect:Dialect.Sqlite
        { (command A.Update [ assignment ]) with where_ = Some (A.Exists nested_select) }
    ;;

    let%test_unit "UPDATE lowering rejects nested unsupported HAVING" =
      assert (
        is_sqlite_unsupported
          (Lower.command ~dialect:Dialect.Sqlite (command A.Update [ bad_assignment ])))
    ;;

    let%test_unit "UPSERT lowering rejects DEFAULT assignments on SQLite" =
      let ast =
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
      in
      assert (is_sqlite_unsupported (Lower.command ~dialect:Dialect.Sqlite ast))
    ;;

    let%test_unit "RETURNING lowering rejects nested unsupported HAVING" =
      let query =
        A.Returning
          { command = command A.Insert [ assignment ]; projection = [ bad_expression ] }
      in
      assert (is_sqlite_unsupported (Lower.result_query ~dialect:Dialect.Sqlite query))
    ;;

    let%test "INTERSECT ALL is unsupported on SQLite" =
      is_sqlite_unsupported
        (Lower.result_query ~dialect:Dialect.Sqlite (unsupported_set A.Intersect_all))
    ;;

    let%test "EXCEPT ALL is unsupported on SQLite" =
      is_sqlite_unsupported
        (Lower.result_query ~dialect:Dialect.Sqlite (unsupported_set A.Except_all))
    ;;

    let%test "PostgreSQL accepts the nested HAVING query" =
      not (Lower.select_has_unsupported_having ~dialect:Dialect.Postgresql nested_select)
    ;;
  end)
;;

let%test_unit "exactly-one proof rejects compound SELECTs" =
  let table : unit Table.t = Table.v_exn "items" in
  let id = Column.v_exn table "id" Db_type.int in
  let selected =
    Query.(from table |> select (fun row -> Projection.expr (Expr.column row id)))
  in
  let compound = Query.union selected selected in
  let forged = { compound with Result_query.requires_exactly_one = true } in
  match Compiler.compile ~dialect:Dialect.Sqlite forged with
  | Error Compile_error.Exactly_one_query_not_proven -> ()
  | Error error -> failwith (Compile_error.to_string error)
  | Ok _ -> failwith "compound SELECT was accepted as exactly one row"
;;

let%test_unit "multiset decoder keeps defensive JSON diagnostics" =
  let int_projection = Projection.expr (Expr.constant Db_type.int 1) in
  let decode projection value =
    Projection.decode_json_rows projection ~path:[] (`List [ `List [ value ] ])
  in
  (match decode int_projection (`Bool true) with
   | Error message -> assert (String.is_substring message ~substring:"got boolean")
   | Ok _ -> failwith "boolean JSON was accepted as an integer");
  (match decode int_projection (`List []) with
   | Error message -> assert (String.is_substring message ~substring:"got compound")
   | Ok _ -> failwith "compound JSON was accepted as an integer");
  let bool_projection = Projection.expr (Expr.constant Db_type.bool false) in
  List.iter
    [ `Intlit "2"; `Float 2.0 ]
    ~f:(fun value ->
      match decode bool_projection value with
      | Error message -> assert (String.is_substring message ~substring:"got number")
      | Ok _ -> failwith "a JSON number was accepted as a boolean");
  (match Projection.decode_json_rows int_projection ~path:[] (`List [ `List [] ]) with
   | Error message ->
     assert (String.is_substring message ~substring:"projected field count")
   | Ok _ -> failwith "a row with a missing field was accepted");
  (match Projection.decode_json_rows int_projection ~path:[] `Null with
   | Error message -> assert (String.is_substring message ~substring:"expected array")
   | Ok _ -> failwith "a non-array multiset was accepted");
  let int64_projection = Projection.expr (Expr.constant Db_type.int64 1L) in
  (match decode int64_projection (`Intlit "9223372036854775808") with
   | Error message -> assert (String.is_substring message ~substring:"expected int64")
   | Ok _ -> failwith "an out-of-range int64 JSON value was accepted");
  let numeric_projection =
    Projection.expr
      (Expr.constant Db_type.numeric (Decimal.of_string "1" |> Option.value_exn))
  in
  match decode numeric_projection (`Int 1) with
  | Error message -> assert (String.is_substring message ~substring:"expected numeric")
  | Ok _ -> failwith "numeric JSON was accepted by the multiset decoder"
;;

let%test "multiset decoder reports unsupported array and byte fields" =
  let value =
    Pg_array.create ~dimensions:[ 1 ] ~lower_bounds:[ 1 ] ~elements:[ Some 1 ]
    |> Result.ok_or_failwith
  in
  let array_projection =
    Projection.expr (Expr.constant (Db_type.Postgresql.array Db_type.int) value)
  in
  let bytes_projection =
    Projection.expr (Expr.constant Db_type.bytes (Bytes.of_string "a"))
  in
  let decode projection =
    Projection.decode_json_rows projection ~path:[] (`List [ `List [ `String "a" ] ])
  in
  (match decode array_projection with
   | Error message ->
     String.is_substring message ~substring:"array fields are unsupported"
   | Ok _ -> false)
  &&
  match decode bytes_projection with
  | Error message -> String.is_substring message ~substring:"byte fields are unsupported"
  | Ok _ -> false
;;

let%test_unit "result-only multiset codecs expose their backend view" =
  let db_type : int list Db_type.t =
    Db_type.json_result
      ~fields:[ Db_type.Pack Db_type.int ]
      ~decode_json:(fun ~path:_ _ -> Ok [])
  in
  assert (String.equal (Db_type.name db_type) "multiset");
  let verify_view : type a. a Db_type.t -> a -> bool =
    fun db_type value ->
    match Db_type.view db_type with
    | Db_type.Map { repr = Db_type.Text_type; encode; decode; name } ->
      String.equal name "multiset"
      && Result.is_error (encode value)
      && Result.is_error (decode "{")
    | _ -> false
  in
  assert (verify_view db_type [])
;;

let%test "named and array backend views preserve text transport" =
  let named =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "kind")
      Db_type.text
  in
  let array = Db_type.Postgresql.array named in
  let named_ok =
    match Db_type.view named with
    | Db_type.Named { schema; name; repr = Db_type.Text_type } ->
      String.equal schema "public" && String.equal name "kind"
    | _ -> false
  in
  let array_ok =
    match Db_type.view array with
    | Db_type.Array { encode; decode } ->
      let value =
        Pg_array.create ~dimensions:[ 2 ] ~lower_bounds:[ 1 ] ~elements:[ Some "a"; None ]
        |> Result.ok_or_failwith
      in
      (match encode value with
       | Error _ -> false
       | Ok source ->
         (match decode source with
          | Error _ -> false
          | Ok decoded ->
            List.equal
              (Option.equal String.equal)
              (Pg_array.elements decoded)
              [ Some "a"; None ]))
    | _ -> false
  in
  named_ok && array_ok
;;

let%test "multiset result type cannot be used as a PostgreSQL text parameter" =
  let db_type : int list Db_type.t =
    Db_type.json_result
      ~fields:[ Db_type.Pack Db_type.int ]
      ~decode_json:(fun ~path:_ _ -> Ok [])
  in
  Result.is_error (Db_type.pg_text_encode db_type [])
  && Result.is_error (Db_type.pg_text_decode db_type "[]")
  && String.equal (Db_type.postgresql_type_name db_type) "jsonb"
  && (not (Db_type.needs_postgresql_cast db_type))
  && Option.is_none (Db_type.sqlite_unsupported_type db_type)
;;

let%test "named and array fields are rejected in multiset JSON" =
  let named =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "binary")
      Db_type.bytes
  in
  let array = Db_type.Postgresql.array Db_type.int in
  Option.is_some (Db_type.unsupported_multiset_type ~path:[] named)
  && Option.is_some (Db_type.unsupported_multiset_type ~path:[] array)
;;

let%test_module "corrupt result kinds report their invariant" =
  (module struct
    let table : unit Table.t = Table.v_exn "items"
    let id = Column.v_exn table "id" Db_type.int

    let selected =
      Query.(from table |> select (fun row -> Projection.expr (Expr.column row id)))
    ;;

    let returning_ast =
      A.Returning { command = command A.Insert [ assignment ]; projection = [ column 0 ] }
    ;;

    let corrupt_select = { selected with Result_query.ast = returning_ast }

    let fails_with message f =
      try
        f ();
        false
      with
      | Failure actual -> String.is_substring actual ~substring:message
    ;;

    let%test "multiset needs a SELECT result" =
      fails_with "Query.multiset requires a SELECT query" (fun () ->
        ignore (Query.multiset corrupt_select))
    ;;

    let%test "derived relation needs a SELECT result" =
      fails_with "a derived table requires a SELECT query" (fun () ->
        ignore
          (Derived_table.create
             ~table
             ~columns:(fun row -> Projection.expr (Expr.column row id))
             corrupt_select))
    ;;

    let%test "INSERT SELECT needs a SELECT result" =
      fails_with "INSERT SELECT input must be a SELECT query" (fun () ->
        ignore
          Insert.(into table |> from_select (Columns.column id) corrupt_select |> command))
    ;;

    let%test "set operation checks its left result" =
      fails_with "set operation left input must be SELECT" (fun () ->
        ignore (Query.union corrupt_select selected))
    ;;

    let%test "set operation checks its right result" =
      fails_with "set operation right input must be SELECT" (fun () ->
        ignore (Query.union selected corrupt_select))
    ;;

    let%test "returning CTE needs a RETURNING result" =
      let returning =
        Insert.(
          into table
          |> set id 1
          |> returning (fun row -> Projection.expr (Expr.column row id)))
      in
      let corrupt_returning =
        { returning with Result_query.ast = A.Select (A.Simple select) }
      in
      fails_with "returning CTE requires a RETURNING query" (fun () ->
        ignore
          (Cte.Postgresql.returning
             ~table
             ~columns:(fun row -> Projection.expr (Expr.column row id))
             corrupt_returning))
    ;;
  end)
;;

let%test_module "renderer reports corrupt AST invariants" =
  (module struct
    let bad_column = A.Param (A.Value (Db_type.Value (Db_type.int, 1)))

    let fails_with message f =
      try
        f ();
        false
      with
      | Failure actual -> String.is_substring actual ~substring:message
    ;;

    let%test "relation column must be a column expression" =
      let relation : A.relation =
        { query = A.Simple select
        ; columns = [ bad_column ]
        ; column_types = [ Db_type.Pack Db_type.int ]
        ; result_types = [ Db_type.Pack Db_type.int ]
        }
      in
      fails_with "relation column 1 is not a column expression" (fun () ->
        ignore (Renderer.relation_column_names relation))
    ;;

    let%test "VALUES descriptor must contain column expressions" =
      let values : A.values =
        { descriptor_source_id = 0; columns = [ bad_column ]; rows = [] }
      in
      fails_with "VALUES descriptor column 1 is not a column expression" (fun () ->
        ignore (Renderer.render_values_source ~aliases:[] values Renderer.initial_state))
    ;;

    let%test "CTE descriptor must contain column expressions" =
      let cte : A.cte =
        { cte_id = 1
        ; columns = [ bad_column ]
        ; column_types = [ Db_type.Pack Db_type.int ]
        ; result_types = [ Db_type.Pack Db_type.int ]
        ; materialization = None
        ; body = A.Select_body (A.Simple select)
        }
      in
      fails_with "CTE descriptor column 1 is not a column expression" (fun () ->
        ignore (Renderer.cte_column_names cte))
    ;;

    let%test "DML target must be a table" =
      fails_with "DML target must be a base table" (fun () ->
        ignore (Renderer.render_target_source { source_id = 0; kind = A.Cte 1 }))
    ;;

    let%test "INSERT without input reports its invariant" =
      let invalid = { (command A.Insert [ assignment ]) with insert_input = None } in
      fails_with "INSERT command has no input" (fun () ->
        ignore (Renderer.command ~dialect:Dialect.Postgresql invalid))
    ;;

    let%test "INSERT with mixed inputs reports its invariant" =
      let invalid =
        { (command A.Insert [ assignment ]) with insert_input = Some A.Mixed_sources }
      in
      fails_with "INSERT mixes VALUES and SELECT inputs" (fun () ->
        ignore (Renderer.command ~dialect:Dialect.Postgresql invalid))
    ;;
  end)
;;
