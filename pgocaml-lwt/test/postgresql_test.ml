open! Base
open Typed_sql
open Infix
module Adapter = Typed_sql_pgocaml_lwt
module Pgocaml = Adapter.Pgocaml

let ( let* ) = Lwt.bind
let ( >>= ) = Lwt.bind

let or_fail = function
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Adapter.error_to_string error)
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
    let statement =
      Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun _ -> query)
    in
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
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
      Insert.(into Numeric_item.table |> set Numeric_item.amount_column amount |> command))
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
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
      Insert.(into Sqlstate_item.table |> set Sqlstate_item.code_column code |> command))
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
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
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
        |> command))
  in
  let* _ = Adapter.run ~conn insert () >>= or_fail in
  let select =
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =$ 1L)
        |> select Item.projection))
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
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =$ 1L)
        |> select (fun item -> Projection.expr (Item.timestamp item))))
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
    Statement.For_dialect.query_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.select_one (Expr.constant rejecting_encode "value"))
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
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(
        from Item.table
        |> select (fun item -> Projection.expr (Expr.column item decoded_column))))
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
    Statement.For_dialect.command_exn ~dialect:Dialect.postgresql (fun _ ->
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
        |> command))
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
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =$ id)
        |> select (fun _ -> Projection.expr Expr.count_all)))
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
    Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun params ->
      let id = params.column ~name:"id" Item.id_column ~get:Fn.id in
      Query.(
        from Item.table
        |> where (fun item -> Item.id item =. id)
        |> select (fun item -> Projection.expr (Item.id item))))
  in
  let* bound = Adapter.run ~conn by_id 2L >>= or_fail in
  if not (List.equal Int64.equal bound [ 2L ]) then
    failwith "PG'OCaml bind parameter returned wrong rows";
  let many =
    Statement.For_dialect.expect_one_exn ~dialect:Dialect.postgresql (fun _ ->
      Query.(from Item.table |> select (fun item -> Projection.expr (Item.id item))))
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
         Statement.For_dialect.query_one_exn ~dialect:Dialect.postgresql (fun _ ->
           Query.select_one (Expr.constant Db_type.int64 1L))
       in
       let* value = Adapter.run ~conn query () >>= or_fail in
       if not Int64.(value = 1L) then
         failwith "PG'OCaml query returned wrong value";
       let* () = test_codecs conn in
       let* () = test_transactions conn in
       let* () = test_queries conn in
       let* () = test_sqlstates conn in
       Lwt.return_unit)
    (fun () -> Pgocaml.close conn)
;;

let () = Lwt_main.run (main ())
