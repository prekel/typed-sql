open! Base

let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let reset conn = exec conn "TRUNCATE native_items"

let predicates conn =
  reset conn;
  [%pgsql
    conn
      "INSERT INTO native_items (id, mood, small_value, nested_value, required_value) VALUES (${1l}, ${\"happy\"}, ${7}, ${8}, ${\"Ada\"}), (${2l}, ${\"sad\"}, ${9}, ${10}, ${\"Grace\"}), (${3l}, ${\"happy\"}, ${11}, ${12}, ${\"Lin\"})"];
  let values : int32 list =
    [%pgsql
      conn
        "SELECT id FROM native_items WHERE NOT (id < ${2l}) AND id BETWEEN 1 AND 3 OR required_value ILIKE 'a%' ORDER BY id LIMIT ${2L} OFFSET ${1L}"]
  in
  assert (List.equal Int32.equal values [ 2l; 3l ]);
  let values : int32 list =
    [%pgsql
      conn
        "SELECT id FROM native_items WHERE nullable_numbers IS NULL AND required_value NOT LIKE 'G%' ORDER BY id OFFSET 1 LIMIT ALL"]
  in
  assert (List.equal Int32.equal values [ 3l ]);
  let values : int32 list =
    [%pgsql conn "SELECT id FROM native_items ORDER BY id LIMIT $?{None} OFFSET $?{None}"]
  in
  assert (List.equal Int32.equal values [ 1l; 2l; 3l ]);
  let values : int32 list =
    [%pgsql
      conn "SELECT id FROM native_items WHERE small_value > ${8} AND mood <> 'happy'"]
  in
  assert (List.equal Int32.equal values [ 2l ])
;;

let static_in conn =
  reset conn;
  [%pgsql
    conn
      "INSERT INTO native_items (id, mood) VALUES (${1l}, ${\"happy\"}), (${2l}, ${\"sad\"}), (${3l}, ${\"happy\"})"];
  assert (
    List.equal
      Int32.equal
      [%pgsql conn "SELECT id FROM native_items WHERE id IN (${1l}, ${3l}) ORDER BY id"]
      [ 1l; 3l ]);
  assert (
    List.equal
      Int32.equal
      [%pgsql conn "SELECT id FROM native_items WHERE id NOT IN (1, 3)"]
      [ 2l ]);
  assert (
    List.equal
      Int32.equal
      [%pgsql
        conn "SELECT id FROM native_items WHERE mood IN (${\"happy\"}, NULL) ORDER BY id"]
      [ 1l; 3l ])
;;

let quantifiers conn =
  reset conn;
  [%pgsql conn "INSERT INTO native_items (id) VALUES (${1l}), (${2l})"];
  let values = [ Some 1l; None ] in
  assert (
    List.equal
      Int32.equal
      [%pgsql conn "SELECT id FROM native_items WHERE id = ANY($values)"]
      [ 1l ]);
  let empty = [] in
  assert (List.is_empty [%pgsql conn "SELECT id FROM native_items WHERE id = ANY($empty)"]);
  assert (
    List.equal
      Int32.equal
      [%pgsql conn "SELECT id FROM native_items WHERE id > ALL($empty) ORDER BY id"]
      [ 1l; 2l ])
;;

let domain_arrays conn =
  reset conn;
  let domains = [ Some 7; None ] in
  let numbers = [ Some 1l; None ] in
  let rows : (int option list * int32 option list) list =
    [%pgsql
      conn
        "INSERT INTO native_items (domain_numbers, domain_array) VALUES ($domains, $numbers) RETURNING domain_numbers, domain_array"]
  in
  match rows with
  | [ (left, right) ] ->
    assert (
      List.equal (Option.equal Int.equal) left domains
      && List.equal (Option.equal Int32.equal) right numbers)
  | _ -> failwith "expected domain array values"
;;

let domain_nullability conn =
  reset conn;
  let rows : string option list =
    [%pgsql
      conn
        "INSERT INTO native_items (required_value) VALUES (${\"required\"}) RETURNING required_value"]
  in
  assert (List.equal (Option.equal String.equal) rows [ Some "required" ])
;;

let enum_arrays conn =
  reset conn;
  let values = [ Some "happy"; None; Some "sad" ] in
  let rows : string option list list =
    [%pgsql conn "INSERT INTO native_items (moods) VALUES ($values) RETURNING moods"]
  in
  assert (List.equal (List.equal (Option.equal String.equal)) rows [ values ])
;;

let array_dimensions conn =
  reset conn;
  exec conn "INSERT INTO native_items (numbers) VALUES ('{{1,2},{3,4}}')";
  assert (
    Result.is_error
      (Result.try_with (fun () -> [%pgsql conn "SELECT numbers FROM native_items"])))
;;

let array_bool conn =
  reset conn;
  let value = true in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_bool) VALUES ($values) RETURNING array_bool"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_bool) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_int2 conn =
  reset conn;
  let value = 7 in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_int2) VALUES ($values) RETURNING array_int2"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_int16) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_int4 conn =
  reset conn;
  let value = 42l in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_int4) VALUES ($values) RETURNING array_int4"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_int32) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_int8 conn =
  reset conn;
  let value = 9000000000L in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_int8) VALUES ($values) RETURNING array_int8"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_int64) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_float4 conn =
  reset conn;
  let value = 1.5 in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn
        "INSERT INTO native_items (array_float4) VALUES ($values) RETURNING array_float4"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_float) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_float8 conn =
  reset conn;
  let value = 2.5 in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn
        "INSERT INTO native_items (array_float8) VALUES ($values) RETURNING array_float8"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_float) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_text conn =
  reset conn;
  let value = "a,\"b\\c" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_text) VALUES ($values) RETURNING array_text"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_varchar conn =
  reset conn;
  let value = "NULL" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn
        "INSERT INTO native_items (array_varchar) VALUES ($values) RETURNING array_varchar"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_bpchar conn =
  reset conn;
  let value = "abc" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn
        "INSERT INTO native_items (array_bpchar) VALUES ($values) RETURNING array_bpchar"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_bytea conn =
  reset conn;
  let value = "\000\255" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_bytea) VALUES ($values) RETURNING array_bytea"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_bytea) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_numeric conn =
  reset conn;
  let value = "12.345" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn
        "INSERT INTO native_items (array_numeric) VALUES ($values) RETURNING array_numeric"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_date conn =
  reset conn;
  let value = PGOCaml.date_of_string "2026-10-14" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_date) VALUES ($values) RETURNING array_date"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_date) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_time conn =
  reset conn;
  let value = PGOCaml.time_of_string "12:34:56" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_time) VALUES ($values) RETURNING array_time"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_time) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_timestamp conn =
  reset conn;
  let value = PGOCaml.timestamp_of_string "2026-10-14 12:34:56" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn
        "INSERT INTO native_items (array_timestamp) VALUES ($values) RETURNING array_timestamp"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_timestamp) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_timestamptz conn =
  reset conn;
  exec conn "SET TIME ZONE '+03:00'";
  Exn.protect
    ~finally:(fun () -> exec conn "SET TIME ZONE 'UTC'")
    ~f:(fun () ->
      let value = PGOCaml.timestamptz_of_string "2026-10-14 12:34:56+00" in
      let values = [ Some value; None ] in
      let rows =
        [%pgsql
          conn
            "INSERT INTO native_items (instant, array_timestamptz) VALUES ($value, $values) RETURNING instant, array_timestamptz"]
      in
      match rows with
      | [ (scalar, [ Some element; None ]) ] ->
        assert (
          String.equal
            (PGOCaml.string_of_timestamptz scalar)
            (PGOCaml.string_of_timestamptz element))
      | _ -> failwith "expected array elements to use the scalar PGOCaml conversion")
;;

let array_interval conn =
  reset conn;
  let value = PGOCaml.interval_of_string "2 days" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn
        "INSERT INTO native_items (array_interval) VALUES ($values) RETURNING array_interval"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_interval) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_json conn =
  reset conn;
  let value = "{\"id\":1}" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_json) VALUES ($values) RETURNING array_json"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_jsonb conn =
  reset conn;
  let value = "{\"id\": 1}" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_jsonb) VALUES ($values) RETURNING array_jsonb"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let array_uuid conn =
  reset conn;
  let value = "550e8400-e29b-41d4-a716-446655440000" in
  let values = [ Some value; None ] in
  let rows =
    [%pgsql
      conn "INSERT INTO native_items (array_uuid) VALUES ($values) RETURNING array_uuid"]
  in
  let normalize = List.map ~f:(Option.map ~f:PGOCaml.string_of_uuid) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let () =
  let conn = PGOCaml.connect () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      exec conn "SET TIME ZONE 'UTC'";
      exec conn "CREATE TYPE public.mood AS ENUM ('happy', 'sad')";
      exec conn "CREATE DOMAIN public.small_native AS int2";
      exec conn "CREATE DOMAIN public.nested_native AS public.small_native";
      exec conn "CREATE DOMAIN public.required_native AS text NOT NULL";
      exec conn "CREATE DOMAIN public.intarray_native AS int4[]";
      exec
        conn
        "CREATE TABLE public.native_items (id int4 NOT NULL DEFAULT 42, mood public.mood NOT NULL DEFAULT 'happy', small_value public.small_native NOT NULL DEFAULT 7, nested_value public.nested_native NOT NULL DEFAULT 8, required_value public.required_native DEFAULT 'required', numbers int4[] NOT NULL DEFAULT '{}', nullable_numbers int4[], moods public.mood[] NOT NULL DEFAULT '{}', domain_numbers public.nested_native[] NOT NULL DEFAULT '{}', domain_array public.intarray_native NOT NULL DEFAULT '{}', array_bool pg_catalog.bool[] NOT NULL DEFAULT '{}', array_int2 pg_catalog.int2[] NOT NULL DEFAULT '{}', array_int4 pg_catalog.int4[] NOT NULL DEFAULT '{}', array_int8 pg_catalog.int8[] NOT NULL DEFAULT '{}', array_float4 pg_catalog.float4[] NOT NULL DEFAULT '{}', array_float8 pg_catalog.float8[] NOT NULL DEFAULT '{}', array_text pg_catalog.text[] NOT NULL DEFAULT '{}', array_varchar pg_catalog.varchar[] NOT NULL DEFAULT '{}', array_bpchar pg_catalog.bpchar[] NOT NULL DEFAULT '{}', array_bytea pg_catalog.bytea[] NOT NULL DEFAULT '{}', array_numeric pg_catalog.numeric[] NOT NULL DEFAULT '{}', array_date pg_catalog.date[] NOT NULL DEFAULT '{}', array_time pg_catalog.time[] NOT NULL DEFAULT '{}', array_timestamp pg_catalog.timestamp[] NOT NULL DEFAULT '{}', array_timestamptz pg_catalog.timestamptz[] NOT NULL DEFAULT '{}', array_interval pg_catalog.interval[] NOT NULL DEFAULT '{}', array_json pg_catalog.json[] NOT NULL DEFAULT '{}', array_jsonb pg_catalog.jsonb[] NOT NULL DEFAULT '{}', array_uuid pg_catalog.uuid[] NOT NULL DEFAULT '{}', instant pg_catalog.timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP)";
      List.iter
        [ predicates
        ; static_in
        ; quantifiers
        ; domain_arrays
        ; domain_nullability
        ; enum_arrays
        ; array_dimensions
        ; array_bool
        ; array_int2
        ; array_int4
        ; array_int8
        ; array_float4
        ; array_float8
        ; array_text
        ; array_varchar
        ; array_bpchar
        ; array_bytea
        ; array_numeric
        ; array_date
        ; array_time
        ; array_timestamp
        ; array_timestamptz
        ; array_interval
        ; array_json
        ; array_jsonb
        ; array_uuid
        ]
        ~f:(fun test -> test conn))
;;
