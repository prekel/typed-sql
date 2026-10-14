open! Base
module PGOCaml = Quotation_test.PGOCaml
module Real = Quotation_test.Real_pgocaml

let%test_unit "WHERE and pagination preserve parameter order and codecs" =
  let conn = PGOCaml.create [ [ Some "42" ] ] in
  let id = 42l in
  let active = true in
  let pattern = Some "A%" in
  let limit = Some 2L in
  let offset = 1L in
  let rows : int32 list =
    [%pgsql
      conn
        "SELECT id FROM people WHERE NOT active = $active OR id >= $id AND name ILIKE $?pattern ORDER BY id LIMIT $?limit OFFSET $offset"]
  in
  assert (List.equal Int32.equal rows [ 42l ]);
  assert (
    List.equal
      (Option.equal String.equal)
      conn.parameters
      [ Some "t"; Some "42"; Some "A%"; Some "2"; Some "1" ])
;;

let%test_unit "native array lengths preserve SQL and reuse the prepared statement" =
  let conn = PGOCaml.create [] in
  let select values =
    [%pgsql conn "SELECT id FROM native_items WHERE id = ANY($values)"]
  in
  ignore (select [ Some 1l; Some 2l ] : int32 list);
  ignore (select [ Some 3l ] : int32 list);
  ignore (select [] : int32 list);
  assert (Int.equal (List.length conn.prepared) 1);
  assert (
    String.equal
      (snd (List.hd_exn conn.prepared))
      "SELECT id FROM native_items WHERE id = ANY($1)");
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some "{}" ])
;;

let%test_unit "native array expressions are evaluated once per occurrence" =
  let conn = PGOCaml.create [] in
  let calls = ref 0 in
  let next () =
    Int.incr calls;
    [ Some 1l; None ]
  in
  ignore
    ([%pgsql conn "SELECT id FROM native_items WHERE id = ANY(${next ()})"] : int32 list);
  assert (Int.equal !calls 1)
;;

let%test_unit "fixed IN keeps its parameter count and prepared statement" =
  let conn = PGOCaml.create [] in
  let select first second =
    [%pgsql conn "SELECT id FROM people WHERE id IN ($first, $second)"]
  in
  ignore (select 1l 2l : int32 list);
  ignore (select 3l 4l : int32 list);
  assert (Int.equal (List.length conn.prepared) 1);
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some "3"; Some "4" ])
;;

let%test_unit "enum and domain values keep PGOCaml scalar representations" =
  let conn = PGOCaml.create [ [ Some "happy"; Some "7"; Some "8"; Some "required" ] ] in
  let mood = "happy" in
  let small = 7 in
  let nested = 8 in
  let rows : (string * int * int * string option) list =
    [%pgsql
      conn
        "SELECT mood, small_value, nested_value, required_value FROM native_items WHERE mood = $mood AND small_value = $small AND nested_value = $nested"]
  in
  assert (
    List.equal
      (Option.equal String.equal)
      conn.parameters
      [ Some "happy"; Some "7"; Some "8" ]);
  match rows with
  | [ (mood, small, nested, Some required) ] ->
    assert (
      String.equal mood "happy"
      && Int.equal small 7
      && Int.equal nested 8
      && String.equal required "required")
  | _ -> failwith "expected exact native representations and attribute nullability"
;;

let%test_unit "nullable array keeps a separate outer option" =
  let conn = PGOCaml.create [ [ None ]; [ Some "{1,NULL}" ] ] in
  let rows : int32 option list option list =
    [%pgsql conn "SELECT nullable_numbers FROM native_items"]
  in
  assert (
    List.equal
      (Option.equal (List.equal (Option.equal Int32.equal)))
      rows
      [ None; Some [ Some 1l; None ] ])
;;

let%test_unit "enum arrays decode labels and serialize escaped strings" =
  let conn = PGOCaml.create [ [ Some "{\"happy\",NULL,\"sad\"}" ] ] in
  let values = [ Some "happy"; None; Some "sad" ] in
  let rows : string option list list =
    [%pgsql conn "SELECT moods FROM native_items WHERE moods = $values"]
  in
  assert (List.equal (List.equal (Option.equal String.equal)) rows [ values ]);
  assert (
    List.equal
      (Option.equal String.equal)
      conn.parameters
      [ Some "{\"happy\",NULL,\"sad\"}" ])
;;

let%test_unit "array-of-domain and domain-over-array compose codecs" =
  let conn = PGOCaml.create [ [ Some "{7,NULL}"; Some "{1,NULL}" ] ] in
  let domains = [ Some 7; None ] in
  let array = [ Some 1l; None ] in
  let rows : (int option list * int32 option list) list =
    [%pgsql
      conn
        "SELECT domain_numbers, domain_array FROM native_items WHERE domain_numbers = $domains AND domain_array = $array"]
  in
  match rows with
  | [ (left, right) ] ->
    assert (
      List.equal (Option.equal Int.equal) left domains
      && List.equal (Option.equal Int32.equal) right array)
  | _ -> failwith "expected composed domain and array codecs"
;;

let%test_unit "ANY and ALL infer native array parameters" =
  let conn = PGOCaml.create [] in
  let ids = [ Some 1l; None ] in
  let lower = [ Some 0l ] in
  ignore
    ([%pgsql
       conn "SELECT id FROM native_items WHERE id = ANY($ids) AND id >= ALL($lower)"]
     : int32 list);
  assert (
    List.equal
      (Option.equal String.equal)
      conn.parameters
      [ Some "{\"1\",NULL}"; Some "{\"0\"}" ])
;;

let%test_unit "nested dimensions produce a PGOCaml error" =
  let conn = PGOCaml.create [ [ Some "{{1,2},{3,4}}" ] ] in
  match Result.try_with (fun () -> [%pgsql conn "SELECT numbers FROM native_items"]) with
  | Error (PGOCaml.Error _) -> ()
  | _ -> failwith "expected an array dimension diagnostic"
;;

let%test_unit "native bool array converts each optional element" =
  let value = true in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_bool values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_bool) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_bool FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_bool) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native int2 array converts each optional element" =
  let value = 7 in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_int16 values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_int2) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_int2 FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_int16) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native int4 array converts each optional element" =
  let value = 42l in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_int32 values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_int4) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_int4 FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_int32) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native int8 array converts each optional element" =
  let value = 9000000000L in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_int64 values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_int8) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_int8 FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_int64) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native float4 array converts each optional element" =
  let value = 1.5 in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_float values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_float4) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_float4 FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_float) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native float8 array converts each optional element" =
  let value = 2.5 in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_float values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_float8) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_float8 FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_float) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native text array converts each optional element" =
  let value = "a,\"b\\c" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_string values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_text) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_text FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native varchar array converts each optional element" =
  let value = "NULL" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_string values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_varchar) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_varchar FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native bpchar array converts each optional element" =
  let value = "abc" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_string values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_bpchar) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_bpchar FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native bytea array converts each optional element" =
  let value = "\000\255" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_bytea values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_bytea) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_bytea FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_bytea) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native numeric array converts each optional element" =
  let value = "12.345" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_string values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_numeric) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_numeric FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native date array converts each optional element" =
  let value = Real.date_of_string "2026-10-14" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_date values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_date) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_date FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_date) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native time array converts each optional element" =
  let value = Real.time_of_string "12:34:56" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_time values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_time) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_time FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_time) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native timestamp array converts each optional element" =
  let value = Real.timestamp_of_string "2026-10-14 12:34:56" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_timestamp values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_timestamp) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_timestamp FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_timestamp) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native timestamptz array converts each optional element" =
  let value = Real.timestamptz_of_string "2026-10-14 12:34:56+00" in
  let values = [ Some value; None ] in
  let wire =
    Typed_sql_pgocaml_runtime.string_of_array Real.string_of_timestamptz values
  in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_timestamptz) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_timestamptz FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_timestamptz) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native interval array converts each optional element" =
  let value = Real.interval_of_string "2 days" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_interval values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_interval) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_interval FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_interval) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native json array converts each optional element" =
  let value = "{\"id\":1}" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_string values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_json) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_json FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native jsonb array converts each optional element" =
  let value = "{\"id\":1}" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_string values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_jsonb) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_jsonb FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_string) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;

let%test_unit "native uuid array converts each optional element" =
  let value = "550e8400-e29b-41d4-a716-446655440000" in
  let values = [ Some value; None ] in
  let wire = Typed_sql_pgocaml_runtime.string_of_array Real.string_of_uuid values in
  let conn = PGOCaml.create [ [ Some wire ] ] in
  [%pgsql conn "INSERT INTO native_items (array_uuid) VALUES ($values)"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some wire ]);
  let rows = [%pgsql conn "SELECT array_uuid FROM native_items"] in
  let normalize = List.map ~f:(Option.map ~f:Real.string_of_uuid) in
  assert (
    List.equal
      (List.equal (Option.equal String.equal))
      (List.map rows ~f:normalize)
      [ normalize values ])
;;
