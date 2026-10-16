open! Base
open Typed_sql_private
module A = Ast

let name = Identifier.of_string_exn "id"
let typ = Db_type.Pack Db_type.int

let raw =
  { A.parts = [ A.Raw_text "SELECT 1" ]
  ; fields = [ name, typ ]
  ; top_level_only = false
  ; ctes = []
  }
;;

let output = Projection.raw_field ~name Db_type.int
let query = Result_query.create_select (A.Raw_select raw) output

let%test "raw SELECT cannot bypass the SQLite runtime guard" =
  Result.is_error (Compiler.compile_query_plan ~dialect:Dialect.Sqlite query)
;;

let%test "raw RETURNING cannot bypass the SQLite runtime guard" =
  Result.is_error
    (Compiler.compile_query_plan
       ~dialect:Dialect.Sqlite
       (Result_query.create_raw_returning raw output))
;;

let%test "raw command cannot bypass the SQLite runtime guard" =
  Result.is_error
    (Compiler.compile_command_plan
       ~dialect:Dialect.Sqlite
       (Command.raw { raw with fields = [] }))
;;

let%test "raw command cannot declare rows" =
  Result.is_error (Validator.command_statement (A.Raw_command raw))
;;

let%test "a template containing only a bind is not a statement" =
  let raw =
    { raw with
      parts =
        [ A.Raw_bind
            { expected = typ; value = A.Param (A.Value (Db_type.Value (Db_type.int, 1))) }
        ]
    }
  in
  Result.is_error (Validator.result_query (A.Select (A.Raw_select raw)))
;;

let%test_unit "raw CTE bodies cannot bypass SQLite guards" =
  assert (
    Option.is_some
      (Lower.sqlite_unsupported_cte
         { A.cte_id = 0
         ; columns = []
         ; column_types = []
         ; result_types = []
         ; materialization = None
         ; body = A.Raw_returning_body raw
         }));
  assert (
    Option.is_some
      (Lower.sqlite_unsupported_cte
         { A.cte_id = 0
         ; columns = []
         ; column_types = []
         ; result_types = []
         ; materialization = None
         ; body = A.Raw_command_body raw
         }))
;;

let%test "raw decoder reads positional JSON without SQL expressions" =
  match Projection.decode_json_rows output ~path:[] (`List [ `List [ `Int 7 ] ]) with
  | Ok rows -> List.equal Int.equal rows [ 7 ]
  | Error _ -> false
;;

let%test "raw fields cannot masquerade as DSL expressions" =
  Result.is_error (Result.try_with (fun () -> Projection.expressions output))
;;

let%test "raw SELECT does not manufacture an exactly-one proof" =
  Result.is_error
    (Compiler.compile_query_plan
       ~dialect:Dialect.Postgresql
       (Result_query.create_select ~requires_exactly_one:true (A.Raw_select raw) output))
;;

let%test "raw RETURNING does not manufacture an exactly-one proof" =
  let query = Result_query.create_raw_returning raw output in
  Result.is_error
    (Compiler.compile_query_plan
       ~dialect:Dialect.Postgresql
       { query with requires_exactly_one = true })
;;

let%test "raw output builder rejects an ordinary SQL projection" =
  Result.is_error
    (Result.try_with (fun () ->
       Raw_sql.Postgresql.select
         ~output:(Projection.expr (Expr.constant Db_type.int 1))
         [ A.Raw_text "SELECT 1" ]))
;;
