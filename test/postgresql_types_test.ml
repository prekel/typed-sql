open! Base
open Typed_sql
open Statement_compile
open Infix

let good result = Result.is_ok result
let bad result = Result.is_error result
let date source = Date.of_string source |> Option.value_exn

let%test "local timestamp preserves microseconds" =
  match Local_timestamp.of_string "2024-02-29 23:04:05.001234" with
  | Error _ -> false
  | Ok value ->
    String.equal (Local_timestamp.to_string value) "2024-02-29 23:04:05.001234"
    && Int.equal (Local_timestamp.microsecond value) 1_234
    && Int.equal (Local_timestamp.hour value) 23
    && Int.equal (Local_timestamp.minute value) 4
    && Int.equal (Local_timestamp.second value) 5
    && Date.equal (Local_timestamp.date value) (date "2024-02-29")
;;

let%test "local timestamp accepts whole seconds" =
  match Local_timestamp.of_string "2024-01-02 03:04:05" with
  | Ok value -> String.equal (Local_timestamp.to_string value) "2024-01-02 03:04:05"
  | Error _ -> false
;;

let%test "local timestamp rejects invalid fields and syntax" =
  List.for_all
    [ "2024-02-30 12:00:00"
    ; "2024-01-01 24:00:00"
    ; "2024-01-01 12:60:00"
    ; "2024-01-01 12:00:60"
    ; "2024-01-01 12:00:00.1234567"
    ; "2024-01-01 12:00:00Z"
    ; "2024-01-01 12:00:00."
    ; "2024-01-01 12:00:00.12x"
    ; "2024-01-01 12:00:00+03"
    ; "2024-01-01T12:00:00"
    ; "2024-01-01 12-00-00"
    ; "short"
    ]
    ~f:(fun source -> bad (Local_timestamp.of_string source))
;;

let%test "local timestamp constructor checks fields" =
  let date = date "2024-01-01" in
  List.for_all
    [ 24, 0, 0, 0
    ; -1, 0, 0, 0
    ; 0, 60, 0, 0
    ; 0, -1, 0, 0
    ; 0, 0, 60, 0
    ; 0, 0, -1, 0
    ; 0, 0, 0, 1_000_000
    ; 0, 0, 0, -1
    ]
    ~f:(fun (hour, minute, second, microsecond) ->
      bad (Local_timestamp.create ~date ~hour ~minute ~second ~microsecond))
;;

let%test "interval preserves independent components and negative time" =
  match Interval.of_string "1 year 2 mons -3 days -04:05:06.123456" with
  | Error _ -> false
  | Ok value ->
    Int.equal (Interval.months value) 14
    && Int.equal (Interval.days value) (-3)
    && Int64.equal (Interval.microseconds value) (-14_706_123_456L)
    && String.equal (Interval.to_string value) "14 mons -3 days -4:05:06.123456"
;;

let%test "interval handles ago and minimum int64" =
  let ago = Interval.of_string "2 months 3 days 04:05:06 ago" in
  let extreme = Interval.create ~months:0 ~days:0 ~microseconds:Int64.min_value in
  match ago with
  | Error _ -> false
  | Ok value ->
    Int.equal (Interval.months value) (-2)
    && Int.equal (Interval.days value) (-3)
    && Int64.(Interval.microseconds value < 0L)
    && String.is_suffix (Interval.to_string extreme) ~suffix:"-2562047788:00:54.775808"
;;

let%test "interval rejects malformed input" =
  List.for_all
    [ "one day"
    ; "2 fortnights"
    ; "12:99:00"
    ; "12:00:99"
    ; "12:00"
    ; "x:00:00"
    ; "12:00:00.1234567"
    ; "12:00:00.12x"
    ; "1 day trailing"
    ]
    ~f:(fun source -> bad (Interval.of_string source))
;;

let%test "interval accepts a positive time sign" =
  match Interval.of_string "+01:02:03" with
  | Ok value -> Int64.equal (Interval.microseconds value) 3_723_000_000L
  | Error _ -> false
;;

let%test "interval accepts PostgreSQL unit spellings" =
  match Interval.of_string "2 years 1 mon 1 month 3 days" with
  | Ok value -> Int.equal (Interval.months value) 26 && Int.equal (Interval.days value) 3
  | Error _ -> false
;;

let%test "array text keeps quoted null, escapes and bounds" =
  let decode text = Ok text in
  let source = {|[0:1][3:4]={{"NULL","a,b"},{NULL,"a\"b\\c"}}|} in
  match Pg_array.of_string ~decode source with
  | Error _ -> false
  | Ok value ->
    List.equal Int.equal (Pg_array.dimensions value) [ 2; 2 ]
    && List.equal Int.equal (Pg_array.lower_bounds value) [ 0; 3 ]
    && List.equal
         (Option.equal String.equal)
         (Pg_array.elements value)
         [ Some "NULL"; Some "a,b"; None; Some "a\"b\\c" ]
    && Result.equal
         String.equal
         String.equal
         (Pg_array.to_string ~encode:(fun text -> Ok text) value)
         (Ok source)
;;

let%test "array text handles empty and one-dimensional arrays" =
  let decode text = Ok text in
  match Pg_array.of_string ~decode "{}", Pg_array.of_string ~decode "{a,NULL,b}" with
  | Ok empty, Ok populated ->
    List.equal Int.equal (Pg_array.dimensions empty) [ 0 ]
    && List.is_empty (Pg_array.elements empty)
    && List.equal
         (Option.equal String.equal)
         (Pg_array.elements populated)
         [ Some "a"; None; Some "b" ]
  | _ -> false
;;

let%test "array parser preserves a negative lower bound" =
  match Pg_array.of_string ~decode:(fun text -> Ok text) "[-1:0]={a,b}" with
  | Error _ -> false
  | Ok value -> List.equal Int.equal (Pg_array.lower_bounds value) [ -1 ]
;;

let%test "array constructor rejects invalid shapes" =
  List.for_all
    [ [ 2 ], [ 1; 1 ], [ Some 1 ]
    ; [ -1 ], [ 1 ], []
    ; [ Int.max_value; 2 ], [ 1; 1 ], []
    ; [ 2 ], [ 1 ], [ Some 1 ]
    ]
    ~f:(fun (dimensions, lower_bounds, elements) ->
      bad (Pg_array.create ~dimensions ~lower_bounds ~elements))
;;

let%test "array constructors and text handle zero-dimensional and padded input" =
  let empty =
    Pg_array.create ~dimensions:[] ~lower_bounds:[] ~elements:[] |> Result.ok_or_failwith
  in
  let padded =
    Pg_array.of_string ~decode:(fun text -> Ok text) " [ +1:2 ] = { a , b } "
  in
  Result.equal
    String.equal
    String.equal
    (Pg_array.to_string ~encode:(fun text -> Ok text) empty)
    (Ok "{}")
  &&
  match padded with
  | Error _ -> false
  | Ok value ->
    List.equal Int.equal (Pg_array.dimensions value) [ 2 ]
    && List.equal
         (Option.equal String.equal)
         (Pg_array.elements value)
         [ Some "a"; Some "b" ]
    && Result.equal
         String.equal
         String.equal
         (Pg_array.to_string ~encode:(fun text -> Ok text) value)
         (Ok {|{"a","b"}|})
;;

let%test "array parser rejects syntax, bounds and ragged dimensions" =
  List.for_all
    [ "{a,}"
    ; "{,a}"
    ; "{\"unterminated}"
    ; "{\"escape\\}"
    ; "{\"escape\\"
    ; "{{a},{b,c}}"
    ; "[1:3]={a,b}"
    ; "[x:2]={a,b}"
    ; "[1:x]={a,b}"
    ; "[1:2]{a,b}"
    ; "{a}trailing"
    ; "{a"
    ]
    ~f:(fun source -> bad (Pg_array.of_string ~decode:(fun text -> Ok text) source))
;;

let%test "descriptor names preserve named and array SQL identities" =
  let named =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "custom")
      Db_type.text
  in
  String.equal (Db_type.name named) "public.custom"
  && String.equal (Db_type.name (Db_type.Postgresql.array named)) "array(public.custom)"
;;

let%test "array element decoder and encoder errors propagate" =
  bad (Pg_array.of_string ~decode:(fun _ -> Error "bad") "{x}")
  &&
  match Pg_array.create ~dimensions:[ 1 ] ~lower_bounds:[ 1 ] ~elements:[ Some 1 ] with
  | Error _ -> false
  | Ok value -> bad (Pg_array.to_string ~encode:(fun _ -> Error "bad") value)
;;

let%test "PostgreSQL text transport round-trips simple types" =
  let roundtrip typ value equal =
    match Db_type.Postgresql.encode_text typ value with
    | Error _ -> false
    | Ok text ->
      (match Db_type.Postgresql.decode_text typ text with
       | Error _ -> false
       | Ok decoded -> equal value decoded)
  in
  roundtrip Db_type.bool true Bool.equal
  && roundtrip Db_type.int 42 Int.equal
  && roundtrip Db_type.int64 42L Int64.equal
  && roundtrip Db_type.float 1.25 Float.equal
  && roundtrip Db_type.text "x" String.equal
  && roundtrip Db_type.bytes (Bytes.of_string "\000\255") Bytes.equal
  && roundtrip Db_type.date (date "2024-01-02") Date.equal
  && roundtrip
       Db_type.uuid
       (Uuid.of_string_exn "00000000-0000-0000-0000-000000000001")
       Uuid.equal
;;

let%test "PostgreSQL text transport reports invalid values" =
  List.for_all
    [ bad (Db_type.Postgresql.decode_text Db_type.bool "maybe")
    ; good (Db_type.Postgresql.decode_text Db_type.bool "false")
    ; bad (Db_type.Postgresql.decode_text Db_type.int "x")
    ; bad (Db_type.Postgresql.decode_text Db_type.int64 "x")
    ; bad (Db_type.Postgresql.decode_text Db_type.float "x")
    ; bad (Db_type.Postgresql.decode_text Db_type.bytes "\\x0")
    ; bad (Db_type.Postgresql.decode_text Db_type.bytes "\\xzz")
    ; bad (Db_type.Postgresql.decode_text Db_type.bytes "plain")
    ; bad (Db_type.Postgresql.decode_text Db_type.date "bad")
    ; bad (Db_type.Postgresql.decode_text Db_type.uuid "bad")
    ]
    ~f:Fn.id
;;

let%test "PostgreSQL text transport accepts abbreviated boolean output" =
  Result.equal
    Bool.equal
    String.equal
    (Db_type.Postgresql.decode_text Db_type.bool "t")
    (Ok true)
  && Result.equal
       Bool.equal
       String.equal
       (Db_type.Postgresql.decode_text Db_type.bool "f")
       (Ok false)
;;

let%test "PostgreSQL text transport follows named, mapped and array representations" =
  let schema = Identifier.of_string_exn "public" in
  let name = Identifier.of_string_exn "custom" in
  let named = Db_type.Postgresql.named ~schema ~name Db_type.int in
  let mapped =
    Db_type.map
      ~name:"successor"
      ~encode:(fun value -> Ok (value - 1))
      ~decode:(fun value -> Ok (value + 1))
      named
  in
  let array = Db_type.Postgresql.array mapped in
  let value =
    Pg_array.create ~dimensions:[ 2 ] ~lower_bounds:[ 0 ] ~elements:[ Some 42; None ]
    |> Result.ok_or_failwith
  in
  match Db_type.Postgresql.encode_text array value with
  | Error _ -> false
  | Ok text ->
    String.equal text {|[0:1]={"41",NULL}|}
    &&
      (match Db_type.Postgresql.decode_text array text with
      | Ok decoded ->
        List.equal (Option.equal Int.equal) (Pg_array.elements decoded) [ Some 42; None ]
      | Error _ -> false)
;;

let%test "PostgreSQL text transport supports mapped JSON and temporal values" =
  let local =
    Local_timestamp.of_string "2024-01-02 03:04:05.000006" |> Result.ok_or_failwith
  in
  let interval = Interval.create ~months:2 ~days:3 ~microseconds:4_000_000L in
  let json = `Assoc [ "a", `Int 1 ] in
  let roundtrip typ value equal =
    match Db_type.Postgresql.encode_text typ value with
    | Error _ -> false
    | Ok source ->
      (match Db_type.Postgresql.decode_text typ source with
       | Error _ -> false
       | Ok decoded -> equal value decoded)
  in
  roundtrip Db_type.numeric (Decimal.of_string "2.50" |> Option.value_exn) Decimal.equal
  && roundtrip Db_type.timestamp Ptime.epoch Ptime.equal
  && roundtrip Db_type.Postgresql.local_timestamp local (fun left right ->
    String.equal (Local_timestamp.to_string left) (Local_timestamp.to_string right))
  && roundtrip Db_type.Postgresql.interval interval (fun left right ->
    String.equal (Interval.to_string left) (Interval.to_string right))
  && roundtrip Db_type.Postgresql.json json Yojson.Safe.equal
  && roundtrip Db_type.Postgresql.jsonb json Yojson.Safe.equal
;;

let%test "PostgreSQL timestamptz array element accepts server text" =
  good (Db_type.Postgresql.decode_text Db_type.timestamp "2024-01-02 03:04:05.123456+00")
;;

let%test "PostgreSQL text transport rejects mapped and optional errors" =
  let broken =
    Db_type.map
      ~encode:(fun _ -> Error "encode")
      ~decode:(fun _ -> Error "decode")
      Db_type.text
  in
  bad (Db_type.Postgresql.encode_text broken "value")
  && bad (Db_type.Postgresql.decode_text broken "value")
  && bad (Db_type.Postgresql.encode_text (Db_type.option Db_type.int) (Some 1))
  && bad (Db_type.Postgresql.decode_text (Db_type.option Db_type.int) "1")
  && bad (Db_type.Postgresql.decode_text Db_type.numeric "not numeric")
  && bad (Db_type.Postgresql.decode_text Db_type.timestamp "invalid")
  && bad (Db_type.Postgresql.decode_text Db_type.Postgresql.json "{")
  && bad (Db_type.Postgresql.decode_text Db_type.Postgresql.jsonb "{")
  && bad (Db_type.Postgresql.decode_text Db_type.Postgresql.interval "invalid")
  && bad (Db_type.Postgresql.decode_text Db_type.Postgresql.local_timestamp "invalid")
;;

let%test "PostgreSQL named and array parameters carry explicit SQL types" =
  let schema = Identifier.of_string_exn "public" in
  let name = Identifier.of_string_exn "kind" in
  let named = Db_type.Postgresql.named ~schema ~name Db_type.text in
  let array = Db_type.Postgresql.array named in
  let values =
    Pg_array.create ~dimensions:[ 1 ] ~lower_bounds:[ 1 ] ~elements:[ Some "value" ]
    |> Result.ok_or_failwith
  in
  let table : unit Table.t = Table.v_exn "objects" in
  let field = Column.v_exn table "kind" named in
  let query =
    Query.(
      from table
      |> where (fun row -> Expr.column row field =. Expr.constant named "value")
      |> select (fun _ -> Projection.expr (Expr.constant array values)))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error _ -> false
  | Ok compiled ->
    let sql = Compiled_query.sql compiled in
    String.is_substring sql ~substring:"CAST($2 AS \"public\".\"kind\")"
    && String.is_substring sql ~substring:"CAST($1 AS \"public\".\"kind\"[])"
;;

let%test "array_list round-trips a one-dimensional list" =
  let descriptor = Db_type.Postgresql.array_list Db_type.int64 in
  match Db_type.Postgresql.encode_text descriptor [ 1L; 2L ] with
  | Error _ -> false
  | Ok encoded ->
    String.equal encoded {|{"1","2"}|}
    && (match Db_type.Postgresql.decode_text descriptor encoded with
        | Ok decoded -> List.equal Int64.equal decoded [ 1L; 2L ]
        | Error _ -> false)
    &&
      (match Db_type.Postgresql.decode_text descriptor "{}" with
      | Ok decoded -> List.is_empty decoded
      | Error _ -> false)
;;

let%test "array_list rejects shapes it cannot preserve" =
  let descriptor = Db_type.Postgresql.array_list Db_type.int64 in
  List.for_all [ "{{1,2},{3,4}}"; "[2:3]={1,2}"; "{1,NULL}" ] ~f:(fun encoded ->
    bad (Db_type.Postgresql.decode_text descriptor encoded))
;;

let%test "array_list has a useful diagnostic name" =
  String.equal
    (Db_type.name (Db_type.Postgresql.array_list Db_type.int64))
    "array_list(int64)"
;;

let%test "SQLite rejects PostgreSQL named and array descriptors" =
  let schema = Identifier.of_string_exn "public" in
  let named =
    Db_type.Postgresql.named ~schema ~name:(Identifier.of_string_exn "kind") Db_type.text
  in
  let table : unit Table.t = Table.v_exn "objects" in
  let named_column = Column.v_exn table "kind" named in
  let array_column = Column.v_exn table "values" (Db_type.Postgresql.array Db_type.int) in
  let named_query =
    Query.(
      from table |> select (fun row -> Projection.expr (Expr.column row named_column)))
  in
  let array_query =
    Query.(
      from table |> select (fun row -> Projection.expr (Expr.column row array_column)))
  in
  bad (Compiler.compile ~dialect:Dialect.sqlite named_query)
  && bad (Compiler.compile ~dialect:Dialect.sqlite array_query)
;;

let%test "SQLite rejects a list-array descriptor" =
  let table : unit Table.t = Table.v_exn "array_items" in
  let values = Column.v_exn table "values" (Db_type.Postgresql.array_list Db_type.int) in
  let query =
    Query.(from table |> select (fun row -> Projection.expr (Expr.column row values)))
  in
  bad (Compiler.compile ~dialect:Dialect.sqlite query)
;;

let%test "multiset rejects PostgreSQL array fields" =
  let table : unit Table.t = Table.v_exn "array_items" in
  let values = Column.v_exn table "values" (Db_type.Postgresql.array Db_type.int) in
  let query =
    Query.(
      from table
      |> select_exactly_one (fun row ->
        Projection.multiset_agg (Projection.expr (Expr.column row values))))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error (Compile_error.Unsupported_multiset_field_type { type_name; _ }) ->
    String.equal type_name "array"
  | Error _ | Ok _ -> false
;;

let%test "multiset rejects PostgreSQL list-array fields" =
  let table : unit Table.t = Table.v_exn "list_array_items" in
  let values = Column.v_exn table "values" (Db_type.Postgresql.array_list Db_type.int) in
  let query =
    Query.(
      from table
      |> select_exactly_one (fun row ->
        Projection.multiset_agg (Projection.expr (Expr.column row values))))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error (Compile_error.Unsupported_multiset_field_type { type_name; _ }) ->
    String.equal type_name "array"
  | Error _ | Ok _ -> false
;;

let%test "multiset checks the representation of named fields" =
  let table : unit Table.t = Table.v_exn "named_items" in
  let named =
    Db_type.Postgresql.named
      ~schema:(Identifier.of_string_exn "public")
      ~name:(Identifier.of_string_exn "binary_value")
      Db_type.bytes
  in
  let value = Column.v_exn table "value" named in
  let query =
    Query.(
      from table
      |> select_exactly_one (fun row ->
        Projection.multiset_agg (Projection.expr (Expr.column row value))))
  in
  match Compiler.compile ~dialect:Dialect.postgresql query with
  | Error (Compile_error.Unsupported_multiset_field_type { type_name; _ }) ->
    String.equal type_name "bytes"
  | Error _ | Ok _ -> false
;;
