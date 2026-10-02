open! Base
open Typed_sql
open Infix
module Adapter = Typed_sql_pgocaml_lwt
module Pgocaml = Adapter.Pgocaml

module Existing_thread = struct
  type 'a t = 'a Lwt.t

  include Monad.Make (struct
      type nonrec 'a t = 'a t

      let return = Lwt.return
      let bind value ~f = Lwt.bind value f
      let map = `Custom (fun value ~f -> Lwt.map f value)
    end)

  let fail = Lwt.fail
  let catch = Lwt.catch

  type in_channel = Lwt_io.input_channel
  type out_channel = Lwt_io.output_channel

  let open_connection address = Lwt_io.open_connection address
  let output_char = Lwt_io.write_char
  let output_binary_int = Lwt_io.BE.write_int
  let output_string = Lwt_io.write
  let flush = Lwt_io.flush
  let input_char = Lwt_io.read_char
  let input_binary_int = Lwt_io.BE.read_int
  let really_input = Lwt_io.read_into_exactly
  let close_in (channel : in_channel) = Lwt_io.close channel
end

module Existing_pgocaml = PGOCaml_generic.Make (Existing_thread)
module Existing_adapter = Adapter.Make (Existing_pgocaml)

let ( let* ) = Lwt.bind
let ( >>= ) = Lwt.bind

let or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Adapter.error_to_string error)
;;

let test_existing_pgocaml () =
  let* conn = Existing_pgocaml.connect () in
  Lwt.finalize
    (fun () ->
       let statement =
         Statement.query_one
           ~dialect:Dialect.postgresql
           (Query.select_one (Expr.constant Db_type.int64 1L))
       in
       let* result = Existing_adapter.run ~conn statement () in
       match result with
       | Ok 1L -> Lwt.return_unit
       | Ok _ -> Lwt.fail_with "existing PG'OCaml adapter returned wrong value"
       | Error error -> Lwt.fail_with (Existing_adapter.error_to_string error))
    (fun () -> Existing_pgocaml.close conn)
;;

let exec_sql conn sql =
  let* () = Pgocaml.prepare conn ~query:sql () in
  let* _ = Pgocaml.execute conn ~params:[] () in
  Lwt.return_unit
;;

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "pgocaml_items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let boolean_column = Column.v_exn table "boolean_value" Db_type.bool
  let integer_column = Column.v_exn table "integer_value" Db_type.int
  let float_column = Column.v_exn table "float_value" Db_type.float
  let text_column = Column.v_exn table "text_value" Db_type.text
  let bytes_column = Column.v_exn table "bytes_value" Db_type.bytes
  let date_column = Column.v_exn table "date_value" Db_type.date
  let timestamp_column = Column.v_exn table "timestamp_value" Db_type.timestamp
  let uuid_column = Column.v_exn table "uuid_value" Db_type.uuid
  let nullable_column = Column.nullable_v_exn table "nullable_value" Db_type.text
  let id row = Expr.column row id_column
  let text row = Expr.column row text_column
  let timestamp row = Expr.column row timestamp_column

  let projection row =
    Projection.both
      (Projection.both
         (Projection.both
            (Projection.expr (Expr.column row boolean_column))
            (Projection.expr (Expr.column row integer_column)))
         (Projection.both
            (Projection.expr (Expr.column row float_column))
            (Projection.expr (Expr.column row text_column))))
      (Projection.both
         (Projection.both
            (Projection.expr (Expr.column row bytes_column))
            (Projection.expr (Expr.column row date_column)))
         (Projection.both
            (Projection.expr (Expr.column row uuid_column))
            (Projection.expr (Expr.column row nullable_column))))
  ;;
end

module Selected_item = struct
  type row

  let table : row Table.t = Table.v_exn "selected_pgocaml_items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let text_column = Column.v_exn table "text_value" Db_type.text
  let id row = Expr.column row id_column
  let text row = Expr.column row text_column
  let projection row = Projection.pair (id row) (text row)
end

module Numeric_item = struct
  type row

  let table : row Table.t = Table.v_exn "pgocaml_numeric_items"
  let amount_column = Column.v_exn table "amount" Db_type.numeric
  let amount row = Expr.column row amount_column
end

let decimal_exn value =
  match Decimal.of_string value with
  | Some value -> value
  | None -> failwith "invalid fixture decimal"
;;

let test_queries conn =
  let query_many query =
    let statement = Statement.query_many ~dialect:Dialect.postgresql query in
    Adapter.run ~conn statement () >>= or_fail
  in
  let multiset =
    Query.(
      from Item.table
      |> order_by Item.id `Asc
      |> select (fun item ->
        let related =
          Query.(
            from Item.table
            |> where (fun related -> Item.id related >. Item.id item)
            |> order_by Item.id `Asc
            |> select (fun related -> Projection.expr (Item.text related)))
        in
        Projection.both (Projection.expr (Item.id item)) (Query.multiset related)))
  in
  let* nested = query_many multiset in
  if
    not
      (List.equal
         (fun (id, values) (expected_id, expected_values) ->
            Int64.(id = expected_id) && List.equal String.equal values expected_values)
         nested
         [ 1L, [ "transaction" ]; 2L, [] ])
  then
    failwith "PG'OCaml multiset JSON transport failed";
  let selected =
    Derived_table.create
      ~table:Selected_item.table
      ~columns:Selected_item.projection
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =$ 1L)
        |> select (fun item -> Projection.pair (Item.id item) (Item.text item)))
  in
  let derived = Query.(from_derived selected |> select Selected_item.projection) in
  let* derived = query_many derived in
  if
    not
      (List.equal
         (fun (id, text) (expected_id, expected_text) ->
            Int64.(id = expected_id) && String.equal text expected_text)
         derived
         [ 1L, "O'Reilly" ])
  then
    failwith "PG'OCaml derived query failed";
  let cte = Cte.select selected in
  let cte_query =
    Cte.with_result cte ~f:(fun selected ->
      Query.(from_cte selected |> select Selected_item.projection))
  in
  let* from_cte = query_many cte_query in
  if
    not
      (List.equal
         (fun (id, text) (expected_id, expected_text) ->
            Int64.(id = expected_id) && String.equal text expected_text)
         from_cte
         [ 1L, "O'Reilly" ])
  then
    failwith "PG'OCaml CTE query failed";
  let first = Query.select_one (Expr.constant Db_type.int64 1L) in
  let second = Query.select_one (Expr.constant Db_type.int64 2L) in
  let* union = query_many (Query.union_all first second) in
  if not (List.equal Int64.equal union [ 1L; 2L ]) then
    failwith "PG'OCaml set operation failed";
  let* () =
    exec_sql conn "CREATE TABLE pgocaml_numeric_items (amount NUMERIC NOT NULL)"
  in
  let insert_numeric amount =
    Statement.command
      ~dialect:Dialect.postgresql
      Insert.(into Numeric_item.table |> set Numeric_item.amount_column amount |> command)
  in
  let* _ =
    Adapter.run ~conn (insert_numeric (decimal_exn "9223372036854775807")) () >>= or_fail
  in
  let* _ = Adapter.run ~conn (insert_numeric (decimal_exn "1.25")) () >>= or_fail in
  let sum =
    Query.(
      from Numeric_item.table
      |> select (fun item ->
        Projection.expr (Postgresql.Numeric.sum_numeric (Numeric_item.amount item))))
  in
  let* sum = query_many sum in
  (match sum with
   | [ Some value ] when Decimal.equal value (decimal_exn "9223372036854775808.25") -> ()
   | _ -> failwith "PG'OCaml numeric aggregate lost precision");
  Lwt.return_unit
;;

module Sqlstate_item = struct
  type row

  let table : row Table.t = Table.v_exn "pgocaml_sqlstate_cases"
  let code_column = Column.v_exn table "code" Db_type.text
end

let test_sqlstates conn =
  let* () = exec_sql conn "CREATE TABLE pgocaml_sqlstate_cases (code TEXT)" in
  let* () =
    exec_sql
      conn
      "CREATE FUNCTION pgocaml_raise_sqlstate() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'forced SQLSTATE' USING ERRCODE = NEW.code; END $$"
  in
  let* () =
    exec_sql
      conn
      "CREATE TRIGGER raise_sqlstate BEFORE INSERT ON pgocaml_sqlstate_cases FOR EACH ROW EXECUTE FUNCTION pgocaml_raise_sqlstate()"
  in
  let trigger code =
    Statement.command
      ~dialect:Dialect.postgresql
      Insert.(into Sqlstate_item.table |> set Sqlstate_item.code_column code |> command)
  in
  let equal_kind left right =
    match left, right with
    | Adapter.Unique, Adapter.Unique
    | Adapter.Foreign_key, Adapter.Foreign_key
    | Adapter.Not_null, Adapter.Not_null
    | Adapter.Check, Adapter.Check
    | Adapter.Restrict, Adapter.Restrict
    | Adapter.Exclusion, Adapter.Exclusion
    | Adapter.Other, Adapter.Other -> true
    | _ -> false
  in
  Lwt_list.iter_s
    (fun (code, kind) ->
       let* result = Adapter.run ~conn (trigger code) () in
       (match result with
        | Error (Adapter.Constraint_violation { kind = actual; _ })
          when equal_kind kind actual -> ()
        | Error error -> failwith (Adapter.error_to_string error)
        | Ok _ -> failwith "PG'OCaml did not classify SQLSTATE");
       Lwt.return_unit)
    [ "23505", Adapter.Unique
    ; "23503", Adapter.Foreign_key
    ; "23502", Adapter.Not_null
    ; "23514", Adapter.Check
    ; "23001", Adapter.Restrict
    ; "23P01", Adapter.Exclusion
    ; "23000", Adapter.Other
    ]
;;

let date_exn value =
  match Date.of_string value with
  | Some value -> value
  | None -> failwith "invalid fixture date"
;;

let timestamp_exn value =
  match Ptime.of_rfc3339 value with
  | Ok (value, _, _) -> value
  | Error _ -> failwith "invalid fixture timestamp"
;;

let uuid_exn value =
  match Uuid.of_string value with
  | Some value -> value
  | None -> failwith "invalid fixture UUID"
;;

let test_codecs conn =
  let date = date_exn "2024-02-29" in
  let timestamp = timestamp_exn "2024-02-29T12:34:56Z" in
  let uuid = uuid_exn "123e4567-e89b-12d3-a456-426614174000" in
  let bytes = Bytes.of_string "a\000b\\c" in
  let insert =
    Statement.command
      ~dialect:Dialect.postgresql
      Insert.(
        into Item.table
        |> set Item.id_column 1L
        |> set Item.boolean_column true
        |> set Item.integer_column 42
        |> set Item.float_column 1.5
        |> set Item.text_column "O'Reilly"
        |> set Item.bytes_column bytes
        |> set Item.date_column date
        |> set Item.timestamp_column timestamp
        |> set Item.uuid_column uuid
        |> set Item.nullable_column None
        |> command)
  in
  let* _ = Adapter.run ~conn insert () >>= or_fail in
  let select =
    Statement.expect_one
      ~dialect:Dialect.postgresql
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =$ 1L)
        |> select Item.projection)
  in
  let* ( ((boolean, integer), (floating, text))
       , ((actual_bytes, actual_date), (actual_uuid, nullable)) )
    =
    Adapter.run ~conn select () >>= or_fail
  in
  if
    not
      (Bool.equal boolean true
       && Int.(integer = 42)
       && Float.(floating = 1.5)
       && String.equal text "O'Reilly"
       && Bytes.equal actual_bytes bytes
       && Date.equal actual_date date
       && String.equal (Uuid.to_string actual_uuid) (Uuid.to_string uuid)
       && Option.is_none nullable)
  then
    failwith "PG'OCaml codec round-trip failed";
  let select_timestamp =
    Statement.expect_one
      ~dialect:Dialect.postgresql
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =$ 1L)
        |> select (fun item -> Projection.expr (Item.timestamp item)))
  in
  let* actual_timestamp = Adapter.run ~conn select_timestamp () >>= or_fail in
  if not (Ptime.equal actual_timestamp timestamp) then
    failwith "PG'OCaml timestamp round-trip failed";
  let rejecting_encode =
    Db_type.map
      ~name:"rejecting-encode"
      ~encode:(fun _ -> Error "rejected encode")
      ~decode:Result.return
      Db_type.text
  in
  let encode_query =
    Statement.query_one
      ~dialect:Dialect.postgresql
      (Query.select_one (Expr.constant rejecting_encode "value"))
  in
  let* encoded = Adapter.run ~conn encode_query () in
  (match encoded with
   | Error (Adapter.Encode "rejected encode") -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok _ -> failwith "PG'OCaml accepted a rejected mapped encode");
  let rejecting_decode =
    Db_type.map
      ~name:"rejecting-decode"
      ~encode:Result.return
      ~decode:(fun _ -> Error "rejected decode")
      Db_type.text
  in
  let decoded_column = Column.v_exn Item.table "text_value" rejecting_decode in
  let decode_query =
    Statement.expect_one
      ~dialect:Dialect.postgresql
      Query.(
        from Item.table
        |> select (fun item -> Projection.expr (Expr.column item decoded_column)))
  in
  let* decoded = Adapter.run ~conn decode_query () in
  (match decoded with
   | Error (Adapter.Decode "rejected decode") -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok _ -> failwith "PG'OCaml accepted a rejected mapped decode");
  Lwt.return_unit
;;

let test_transactions conn =
  let insert id =
    Statement.command
      ~dialect:Dialect.postgresql
      Insert.(
        into Item.table
        |> set Item.id_column id
        |> set Item.boolean_column false
        |> set Item.integer_column 0
        |> set Item.float_column 0.
        |> set Item.text_column "transaction"
        |> set Item.bytes_column (Bytes.of_string "")
        |> set Item.date_column (date_exn "2024-01-01")
        |> set Item.timestamp_column (timestamp_exn "2024-01-01T00:00:00Z")
        |> set Item.uuid_column (uuid_exn "123e4567-e89b-12d3-a456-426614174000")
        |> set Item.nullable_column None
        |> command)
  in
  let* committed =
    Adapter.transaction ~conn ~f:(fun conn -> Adapter.run ~conn (insert 2L) ())
  in
  let* _ = or_fail committed in
  let* rolled_back =
    Adapter.transaction ~conn ~f:(fun conn ->
      let* result = Adapter.run ~conn (insert 3L) () in
      match result with
      | Error error -> Lwt.return (Error error)
      | Ok _ -> Lwt.return (Error (Adapter.Encode "rollback marker")))
  in
  (match rolled_back with
   | Error (Adapter.Encode "rollback marker") -> ()
   | _ -> failwith "PG'OCaml rollback returned wrong result");
  let count id =
    Statement.expect_one
      ~dialect:Dialect.postgresql
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =$ id)
        |> select (fun _ -> Projection.expr Expr.count_all))
  in
  let* count_committed = Adapter.run ~conn (count 2L) () >>= or_fail in
  let* count_rolled_back = Adapter.run ~conn (count 3L) () >>= or_fail in
  if not (Int64.(count_committed = 1L) && Int64.(count_rolled_back = 0L)) then
    failwith "PG'OCaml transaction lifecycle failed";
  let* duplicate = Adapter.run ~conn (insert 1L) () in
  (match duplicate with
   | Error (Adapter.Constraint_violation { kind = Adapter.Unique; _ }) -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok _ -> failwith "PG'OCaml did not classify unique violation");
  let by_id =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map id = params.column ~name:"id" Item.id_column ~get:Fn.id in
      params.query_many
        Query.(
          from Item.table
          |> where (fun item -> Item.id item =. id)
          |> select (fun item -> Projection.expr (Item.id item))))
  in
  let* bound = Adapter.run ~conn by_id 2L >>= or_fail in
  if not (List.equal Int64.equal bound [ 2L ]) then
    failwith "PG'OCaml bind parameter returned wrong rows";
  let many =
    Statement.expect_one
      ~dialect:Dialect.postgresql
      Query.(from Item.table |> select (fun item -> Projection.expr (Item.id item)))
  in
  let* cardinality = Adapter.run ~conn many () in
  (match cardinality with
   | Error (Adapter.Cardinality { actual = 2; _ }) -> ()
   | _ -> failwith "PG'OCaml did not reject excess rows");
  let* () =
    exec_sql conn "CREATE TABLE pgocaml_deferred_parent (id BIGINT PRIMARY KEY)"
  in
  let* () =
    exec_sql
      conn
      "CREATE TABLE pgocaml_deferred_child (id BIGINT REFERENCES pgocaml_deferred_parent(id) DEFERRABLE INITIALLY DEFERRED)"
  in
  let* commit_error =
    Adapter.transaction ~conn ~f:(fun conn ->
      let* () = exec_sql conn "INSERT INTO pgocaml_deferred_child VALUES (999)" in
      Lwt.return (Ok ()))
  in
  (match commit_error with
   | Error (Adapter.Constraint_violation { kind = Adapter.Foreign_key; _ }) -> ()
   | Error error -> failwith (Adapter.error_to_string error)
   | Ok () -> failwith "PG'OCaml committed a deferred foreign-key violation");
  let* _ = Adapter.run ~conn (count 2L) () >>= or_fail in
  Lwt.return_unit
;;

let prepared_count conn =
  let* rows =
    Pgocaml.inject
      conn
      "SELECT count(*)::bigint FROM pg_prepared_statements WHERE name LIKE 'typed_sql_%'"
  in
  match rows with
  | [ [ Some count ] ] -> Lwt.return (Int.of_string count)
  | _ -> failwith "unexpected pg_prepared_statements result"
;;

let test_prepared_cache conn =
  (match Adapter.Prepared_cache.create ~capacity:0 ~conn () with
   | Error (Adapter.Invalid_cache_capacity 0) -> ()
   | _ -> failwith "invalid prepared cache capacity was accepted");
  let* cache = Adapter.Prepared_cache.create ~capacity:2 ~conn () |> or_fail in
  let int_statement =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      Statement.Parameters.map
        (params.expr ~name:"value" Db_type.int64 ~get:Fn.id)
        ~f:(fun value -> params.query_one (Query.select_one value)))
  in
  let text_statement =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      Statement.Parameters.map
        (params.expr ~name:"value" Db_type.text ~get:Fn.id)
        ~f:(fun value -> params.query_one (Query.select_one value)))
  in
  let upper_statement =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      Statement.Parameters.map
        (params.expr ~name:"value" Db_type.text ~get:Fn.id)
        ~f:(fun value -> params.query_one (Query.select_one (Expr.upper value))))
  in
  let* first = Adapter.Prepared_cache.run cache int_statement 11L >>= or_fail in
  let* second = Adapter.Prepared_cache.run cache int_statement 12L >>= or_fail in
  if not (Int64.(first = 11L) && Int64.(second = 12L)) then
    failwith "cached int64 parameters were reused incorrectly";
  let* concurrent_left, concurrent_right =
    Lwt.both
      (Adapter.Prepared_cache.run cache int_statement 21L >>= or_fail)
      (Adapter.Prepared_cache.run cache int_statement 22L >>= or_fail)
  in
  if not (Int64.(concurrent_left = 21L) && Int64.(concurrent_right = 22L)) then
    failwith "concurrent cached calls mixed parameter values";
  let* count = prepared_count conn in
  if not (Int.equal count 1) then
    failwith "cache did not reuse a prepared statement";
  let* text = Adapter.Prepared_cache.run cache text_statement "text" >>= or_fail in
  if not (String.equal text "text") then
    failwith "cache mixed parameter types";
  let* count = prepared_count conn in
  if not (Int.equal count 2) then
    failwith "cache did not distinguish parameter OIDs";
  let* _ = Adapter.Prepared_cache.run cache int_statement 13L >>= or_fail in
  let* upper = Adapter.Prepared_cache.run cache upper_statement "abc" >>= or_fail in
  if not (String.equal upper "ABC") then
    failwith "cached SQL changed semantics";
  let* count = prepared_count conn in
  if not (Int.equal count 2) then
    failwith "cache exceeded its capacity";
  let* () = Adapter.Prepared_cache.close cache >>= or_fail in
  let* () = Adapter.Prepared_cache.close cache >>= or_fail in
  let* count = prepared_count conn in
  if not (Int.equal count 0) then
    failwith "cache close left server-side statements";
  let* result = Adapter.Prepared_cache.run cache int_statement 14L in
  (match result with
   | Error Adapter.Prepared_cache_closed -> ()
   | _ -> failwith "closed prepared cache accepted an execution");
  let* transaction_cache =
    Adapter.Prepared_cache.create ~capacity:1 ~conn () |> or_fail
  in
  let* rolled_back =
    Adapter.transaction ~conn ~f:(fun _ ->
      let* _ =
        Adapter.Prepared_cache.run transaction_cache int_statement 51L >>= or_fail
      in
      Lwt.return (Error (Adapter.Cardinality { expected = "rollback probe"; actual = 0 })))
  in
  (match rolled_back with
   | Error (Adapter.Cardinality { expected = "rollback probe"; _ }) -> ()
   | _ -> failwith "transaction rollback probe failed");
  let* after_rollback =
    Adapter.Prepared_cache.run transaction_cache int_statement 52L >>= or_fail
  in
  if not Int64.(after_rollback = 52L) then
    failwith "cached statement failed after rollback";
  let* () = exec_sql conn "CREATE TABLE pgocaml_cached_items (id BIGINT PRIMARY KEY)" in
  let cached_items : unit Table.t = Table.v_exn "pgocaml_cached_items" in
  let cached_id = Column.v_exn cached_items "id" Db_type.int64 in
  let insert =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map id = params.column ~name:"id" cached_id ~get:Fn.id in
      params.command Insert.(into cached_items |> set_expr cached_id id |> command))
  in
  let* _ = Adapter.Prepared_cache.run transaction_cache insert 1L >>= or_fail in
  let* duplicate = Adapter.Prepared_cache.run transaction_cache insert 1L in
  (match duplicate with
   | Error (Adapter.Constraint_violation { kind = Adapter.Unique; _ }) -> ()
   | _ -> failwith "cached command lost SQLSTATE classification");
  let* () = Adapter.Prepared_cache.close transaction_cache >>= or_fail in
  let* other_conn = Pgocaml.connect () in
  Lwt.finalize
    (fun () ->
       let* count = prepared_count other_conn in
       if not (Int.equal count 0) then
         failwith "prepared statements leaked to another connection";
       let* other_cache =
         Adapter.Prepared_cache.create ~capacity:1 ~conn:other_conn () |> or_fail
       in
       let* value =
         Adapter.Prepared_cache.run other_cache int_statement 33L >>= or_fail
       in
       if not Int64.(value = 33L) then
         failwith "second connection cache failed";
       let* count = prepared_count other_conn in
       if not (Int.equal count 1) then
         failwith "second connection did not retain its statement";
       Adapter.Prepared_cache.close other_cache >>= or_fail)
    (fun () -> Pgocaml.close other_conn)
;;

let test_rich_types conn =
  let* () = exec_sql conn "CREATE DOMAIN pgocaml_rational AS text" in
  let* () = exec_sql conn "CREATE DOMAIN pgocaml_geometry AS text" in
  let* () =
    exec_sql
      conn
      "CREATE TABLE pgocaml_rich (local_value timestamp without time zone NOT NULL, duration interval NOT NULL, payload jsonb NOT NULL, numbers integer[] NOT NULL, host inet NOT NULL, rational_value pgocaml_rational NOT NULL, geometry_value pgocaml_geometry NOT NULL)"
  in
  let table : unit Table.t = Table.v_exn "pgocaml_rich" in
  let local_column =
    Column.v_exn table "local_value" Schema_test_codecs.Local_float.db_type
  in
  let interval_column = Column.v_exn table "duration" Db_type.Postgresql.interval in
  let json_column = Column.v_exn table "payload" Db_type.Postgresql.jsonb in
  let array_column =
    Column.v_exn table "numbers" (Db_type.Postgresql.array Db_type.int)
  in
  let inet_column = Column.v_exn table "host" Schema_test_codecs.Inet.db_type in
  let rational_type =
    Db_type.map
      ~name:"pgocaml rational fixture"
      ~encode:(fun value -> Ok (Q.to_string value))
      ~decode:(fun value ->
        try Ok (Q.of_string value) with
        | _ -> Error "invalid rational")
      (Db_type.Postgresql.named
         ~schema:(Identifier.of_string_exn "public")
         ~name:(Identifier.of_string_exn "pgocaml_rational")
         Db_type.text)
  in
  let rational_column = Column.v_exn table "rational_value" rational_type in
  let geometry_type =
    Db_type.map
      ~name:"pgocaml geometry fixture"
      ~encode:(fun (x, y) -> Ok (Stdlib.Printf.sprintf "POINT(%g %g)" x y))
      ~decode:(fun value ->
        try Ok (Stdlib.Scanf.sscanf value "POINT(%f %f)" (fun x y -> x, y)) with
        | _ -> Error "invalid geometry")
      (Db_type.Postgresql.named
         ~schema:(Identifier.of_string_exn "public")
         ~name:(Identifier.of_string_exn "pgocaml_geometry")
         Db_type.text)
  in
  let geometry_column = Column.v_exn table "geometry_value" geometry_type in
  let numbers =
    Pg_array.create
      ~dimensions:[ 2; 2 ]
      ~lower_bounds:[ 1; 1 ]
      ~elements:[ Some 1; None; Some 3; Some 4 ]
    |> Result.ok_or_failwith
  in
  let duration = Interval.create ~months:1 ~days:2 ~microseconds:3_000_000L in
  let inet = Ipaddr.Prefix.of_string_exn "2001:db8::/64" in
  let rational = Q.of_string "5/7" in
  let insert =
    Statement.command
      ~dialect:Dialect.postgresql
      Insert.(
        into table
        |> set local_column 12.5
        |> set interval_column duration
        |> set json_column (`Assoc [ "ok", `Bool true ])
        |> set array_column numbers
        |> set inet_column inet
        |> set rational_column rational
        |> set geometry_column (3., 4.)
        |> command)
  in
  let* _ = Adapter.run ~conn insert () >>= or_fail in
  let query =
    Statement.expect_one
      ~dialect:Dialect.postgresql
      Query.(
        from table
        |> select (fun row ->
          let open Projection.Let_syntax in
          let%map local = Projection.expr (Expr.column row local_column)
          and interval = Projection.expr (Expr.column row interval_column)
          and json = Projection.expr (Expr.column row json_column)
          and array = Projection.expr (Expr.column row array_column)
          and host = Projection.expr (Expr.column row inet_column)
          and rational = Projection.expr (Expr.column row rational_column)
          and geometry = Projection.expr (Expr.column row geometry_column) in
          local, interval, json, array, host, rational, geometry))
  in
  let* local, interval, json, array, host, decoded_rational, geometry =
    Adapter.run ~conn query () >>= or_fail
  in
  let x, y = geometry in
  if
    not
      (Float.equal local 12.5
       && Int.equal (Interval.months interval) 1
       && Int.equal (Interval.days interval) 2
       && Int64.equal (Interval.microseconds interval) 3_000_000L
       && String.equal (Yojson.Safe.to_string json) {|{"ok":true}|}
       && List.equal
            (Option.equal Int.equal)
            (Pg_array.elements array)
            (Pg_array.elements numbers)
       && String.equal (Ipaddr.Prefix.to_string host) (Ipaddr.Prefix.to_string inet)
       && Q.equal decoded_rational rational
       && Float.equal x 3.
       && Float.equal y 4.)
  then
    failwith "PG'OCaml rich type round trip failed";
  Lwt.return_unit
;;

let test_array_lookup conn =
  let list_lookup =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map ids =
        params.expr (Db_type.Postgresql.array_list Db_type.int64) ~get:Fn.id
      in
      params.query_many
        Query.(
          from Item.table
          |> where (fun item -> Postgresql.Expr.equals_any_list (Item.id item) ids)
          |> order_by Item.id `Asc
          |> select (fun item -> Projection.expr (Item.id item))))
  in
  let* selected = Adapter.run ~conn list_lookup [ 1L; 2L ] >>= or_fail in
  if not (List.equal Int64.equal selected [ 1L; 2L ]) then
    failwith "PG'OCaml array_list lookup returned wrong rows";
  let* empty = Adapter.run ~conn list_lookup [] >>= or_fail in
  if not (List.is_empty empty) then
    failwith "PG'OCaml empty array lookup returned rows";
  let nullable_lookup =
    Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
      let open Statement.Parameters.Let_syntax in
      let%map ids = params.expr (Db_type.Postgresql.array Db_type.int64) ~get:Fn.id in
      params.query_many
        Query.(
          from Item.table
          |> where (fun item ->
            Condition.not_ (Postgresql.Expr.equals_any (Item.id item) ids))
          |> select (fun item -> Projection.expr (Item.id item))))
  in
  let ids =
    Pg_array.create ~dimensions:[ 2 ] ~lower_bounds:[ 1 ] ~elements:[ Some 2L; None ]
    |> Result.ok_or_failwith
  in
  let* not_matching = Adapter.run ~conn nullable_lookup ids >>= or_fail in
  if not (List.is_empty not_matching) then
    failwith "PG'OCaml NULL array element lost UNKNOWN under NOT";
  Lwt.return_unit
;;

let main () =
  let* conn = Pgocaml.connect () in
  Lwt.finalize
    (fun () ->
       let* () =
         exec_sql
           conn
           "CREATE TABLE pgocaml_items (id BIGINT PRIMARY KEY, boolean_value BOOLEAN NOT NULL, integer_value INTEGER NOT NULL, float_value DOUBLE PRECISION NOT NULL, text_value TEXT NOT NULL, bytes_value BYTEA NOT NULL, date_value DATE NOT NULL, timestamp_value TIMESTAMPTZ NOT NULL, uuid_value UUID NOT NULL, nullable_value TEXT)"
       in
       let query =
         Statement.query_one
           ~dialect:Dialect.postgresql
           (Query.select_one (Expr.constant Db_type.int64 1L))
       in
       let* value = Adapter.run ~conn query () >>= or_fail in
       if not Int64.(value = 1L) then
         failwith "PG'OCaml query returned wrong value";
       let* () = test_codecs conn in
       let* () = test_rich_types conn in
       let* () = test_transactions conn in
       let* () = test_array_lookup conn in
       let* () = test_queries conn in
       let* () = test_sqlstates conn in
       let* () = test_prepared_cache conn in
       let* () = test_existing_pgocaml () in
       Lwt.return_unit)
    (fun () -> Pgocaml.close conn)
;;

let () = Lwt_main.run (main ())
