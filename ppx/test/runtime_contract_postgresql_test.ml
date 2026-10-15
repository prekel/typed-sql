open! Base

let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let with_connection f =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect ~finally:(fun () -> PGOCaml.close conn) ~f:(fun () -> f conn)
;;

let print_value label value = Stdlib.Printf.printf "%s:%S\n" label value

let round_trip ~label ~equal ~encode select values =
  List.iter (None :: List.map values ~f:Option.some) ~f:(fun value ->
    let rows = select value in
    assert (List.equal (Option.equal equal) rows [ value ]);
    List.iter rows ~f:(fun row ->
      print_value label (Option.value_map row ~default:"NULL" ~f:encode)))
;;

(* Each quotation is also compiled by upstream. Its generated unqualified
   Stdlib calls require a local open when the fixture uses Base. *)
let integers conn =
  let small (value : int option) : int option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::smallint"]
  in
  round_trip
    ~label:"int2"
    ~equal:Int.equal
    ~encode:Int.to_string
    small
    [ -32768; -1; 0; 32767 ];
  let integer (value : int32 option) : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::integer"]
  in
  round_trip
    ~label:"int4"
    ~equal:Int32.equal
    ~encode:Int32.to_string
    integer
    [ Int32.min_value; -1l; 0l; Int32.max_value ];
  let bigint (value : int64 option) : int64 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::bigint"]
  in
  round_trip
    ~label:"int8"
    ~equal:Int64.equal
    ~encode:Int64.to_string
    bigint
    [ Int64.min_value; -1L; 0L; Int64.max_value ]
;;

let floating_point conn =
  let equal left right =
    Float.equal left right || (Float.is_nan left && Float.is_nan right)
  in
  let double (value : float option) : float option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::double precision"]
  in
  round_trip
    ~label:"float8"
    ~equal
    ~encode:PGOCaml.string_of_float
    double
    [ 0.; -0.; 1.5; -2.5; 1e300; 1e-300; Float.infinity; Float.neg_infinity; Float.nan ];
  let real (value : float option) : float option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::real"]
  in
  (* PostgreSQL prints float4 with enough digits for float4, then PGOCaml
     parses those digits as float8. Compare after rounding back to float4. *)
  let equal_real left right =
    Int32.equal (Stdlib.Int32.bits_of_float left) (Stdlib.Int32.bits_of_float right)
    || (Float.is_nan left && Float.is_nan right)
  in
  round_trip
    ~label:"float4"
    ~equal:equal_real
    ~encode:PGOCaml.string_of_float
    real
    [ 0.
    ; -0.
    ; 16777216.
    ; -16777216.
    ; 3.4028234663852886e38
    ; 1.1754943508222875e-38
    ; Float.infinity
    ; Float.neg_infinity
    ; Float.nan
    ]
;;

let text conn =
  let select (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::text"]
  in
  round_trip
    ~label:"text"
    ~equal:String.equal
    ~encode:Fn.id
    select
    [ ""; "NULL"; "O'Reilly\\\"\n\t"; "Привет, λ 🐘"; "'); DROP TABLE people; --" ];
  let varchar (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::varchar"]
  in
  round_trip ~label:"varchar" ~equal:String.equal ~encode:Fn.id varchar [ ""; "λ  " ];
  let bpchar (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::bpchar"]
  in
  round_trip ~label:"bpchar" ~equal:String.equal ~encode:Fn.id bpchar [ ""; "abc" ]
;;

let binary conn =
  let select (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::bytea"]
  in
  let values = [ ""; "\000\255\\\""; String.init 256 ~f:Char.of_int_exn ] in
  List.iter [ "hex"; "escape" ] ~f:(fun format ->
    exec conn ("SET bytea_output = '" ^ format ^ "'");
    round_trip ~label:("bytea/" ^ format) ~equal:String.equal ~encode:Fn.id select values)
;;

let booleans conn =
  let select (value : bool option) : bool option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::boolean"]
  in
  round_trip
    ~label:"bool"
    ~equal:Bool.equal
    ~encode:PGOCaml.string_of_bool
    select
    [ false; true ]
;;

let numeric conn =
  let select (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::numeric"]
  in
  round_trip
    ~label:"numeric"
    ~equal:String.equal
    ~encode:Fn.id
    select
    [ "0"; "-123.4500"; "123456789012345678901234567890.000001"; "NaN" ]
;;

let uuid conn =
  let select (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::uuid"]
  in
  round_trip
    ~label:"uuid"
    ~equal:String.equal
    ~encode:Fn.id
    select
    [ "00000000-0000-0000-0000-000000000000"; "ffffffff-ffff-ffff-ffff-ffffffffffff" ]
;;

let temporal conn =
  let compare_encoding encode left right = String.equal (encode left) (encode right) in
  let date value =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::date"]
  in
  round_trip
    ~label:"date"
    ~equal:(compare_encoding PGOCaml.string_of_date)
    ~encode:PGOCaml.string_of_date
    date
    (List.map [ "1970-01-01"; "2000-02-29"; "2038-01-19" ] ~f:PGOCaml.date_of_string);
  let time value =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::time"]
  in
  round_trip
    ~label:"time"
    ~equal:(compare_encoding PGOCaml.string_of_time)
    ~encode:PGOCaml.string_of_time
    time
    (List.map [ "00:00:00"; "23:59:59" ] ~f:PGOCaml.time_of_string);
  let timestamp value =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::timestamp"]
  in
  round_trip
    ~label:"timestamp"
    ~equal:(compare_encoding PGOCaml.string_of_timestamp)
    ~encode:PGOCaml.string_of_timestamp
    timestamp
    (List.map
       [ "1970-01-01 00:00:00"; "2000-02-29 23:59:59" ]
       ~f:PGOCaml.timestamp_of_string);
  let timestamptz value =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::timestamptz"]
  in
  round_trip
    ~label:"timestamptz"
    ~equal:(compare_encoding PGOCaml.string_of_timestamptz)
    ~encode:PGOCaml.string_of_timestamptz
    timestamptz
    (List.map
       [ "1970-01-01 00:00:00+00"; "2000-02-29 23:59:59+00" ]
       ~f:PGOCaml.timestamptz_of_string);
  let interval value =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::interval"]
  in
  round_trip
    ~label:"interval"
    ~equal:(compare_encoding PGOCaml.string_of_interval)
    ~encode:PGOCaml.string_of_interval
    interval
    (List.map
       [ "0 seconds"; "-2 days"; "1 year 2 mons 3 days 4 seconds" ]
       ~f:PGOCaml.interval_of_string)
;;

let documents conn =
  let json (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::json"]
  in
  round_trip
    ~label:"json"
    ~equal:String.equal
    ~encode:Fn.id
    json
    [ "null"; "[true, null, 1]"; "{\"name\": \"λ\"}" ];
  let jsonb (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::jsonb"]
  in
  round_trip
    ~label:"jsonb"
    ~equal:String.equal
    ~encode:Fn.id
    jsonb
    [ "null"; "[true, null, 1]"; "{\"name\": \"λ\"}" ]
;;

let arrays conn =
  let texts (value : string option list option) : string option list option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::text[]"]
  in
  round_trip
    ~label:"text[]"
    ~equal:(List.equal (Option.equal String.equal))
    ~encode:PGOCaml.string_of_string_array
    texts
    [ []
    ; [ None ]
    ; [ Some ""; Some "NULL"; None; Some "a,b"; Some "{}"; Some "a\\\"b"; Some " λ " ]
    ];
  let integers (value : int32 option list option) : int32 option list option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::integer[]"]
  in
  round_trip
    ~label:"int4[]"
    ~equal:(List.equal (Option.equal Int32.equal))
    ~encode:PGOCaml.string_of_int32_array
    integers
    [ []; [ None ]; [ Some Int32.min_value; None; Some Int32.max_value ] ]
;;

let domains conn =
  (* A domain-typed bind makes upstream look for a custom converter. Keep
     built-in codecs at the boundary and apply the domain cast on the server. *)
  let select (value : int option) : int option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::smallint::public.nested_native::smallint"]
  in
  round_trip
    ~label:"nested domain"
    ~equal:Int.equal
    ~encode:Int.to_string
    select
    [ -32768; 0; 32767 ]
;;

let enum_labels conn =
  (* Text at both API boundaries avoids upstream's custom enum converters. *)
  let select (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::text::public.mood::text"]
  in
  round_trip
    ~label:"enum label"
    ~equal:String.equal
    ~encode:Fn.id
    select
    [ "happy"; "sad" ]
;;

let expect_sqlstate ~label ~state ?constraint_name ?table ?column f =
  match f () with
  | _ -> failwith (label ^ ": expected PostgreSQL_Error " ^ state)
  | exception PGOCaml.PostgreSQL_Error (_, fields) ->
    let field name = List.Assoc.find fields name ~equal:Char.equal in
    assert (Option.equal String.equal (field 'C') (Some state));
    List.iter
      [ constraint_name, 'n'; table, 't'; column, 'c' ]
      ~f:(fun (expected, key) ->
        Option.iter expected ~f:(fun expected ->
          assert (Option.equal String.equal (field key) (Some expected))));
    let values =
      List.map [ 'C'; 's'; 't'; 'c'; 'n'; 'd' ] ~f:(fun key ->
        Option.value (field key) ~default:"")
    in
    print_value label (String.concat ~sep:":" values)
;;

let parameter_errors conn =
  let small (value : int) : int option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $value::smallint"]
  in
  List.iter [ -32769; 32768 ] ~f:(fun value ->
    expect_sqlstate ~label:"int2 overflow" ~state:"22003" (fun () -> small value));
  assert (List.equal (Option.equal Int.equal) (small 32767) [ Some 32767 ]);
  let number (value : string) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $value::numeric"]
  in
  expect_sqlstate ~label:"invalid numeric" ~state:"22P02" (fun () -> number "not numeric");
  let uuid (value : string) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $value::uuid"]
  in
  expect_sqlstate ~label:"invalid uuid" ~state:"22P02" (fun () -> uuid "not a uuid");
  let json (value : string) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $value::json"]
  in
  expect_sqlstate ~label:"invalid json" ~state:"22P02" (fun () -> json "{");
  let text (value : string) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $value::text"]
  in
  (match text "\000" with
   | _ -> failwith "expected the PGOCaml driver to reject a NUL text parameter"
   | exception PGOCaml.Error message ->
     assert (String.is_substring message ~substring:"ASCII NIL");
     print_value "NUL text driver error" message);
  expect_sqlstate ~label:"invalid UTF8 text" ~state:"22021" (fun () -> text "\255");
  assert (
    List.equal (Option.equal String.equal) (text "after error") [ Some "after error" ]);
  let enum (value : string) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $value::text::public.mood::text"]
  in
  expect_sqlstate ~label:"invalid enum" ~state:"22P02" (fun () -> enum "unknown");
  let domain (value : string option) : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT $?value::text::public.required_native::text"]
  in
  expect_sqlstate ~label:"domain not null" ~state:"23502" (fun () -> domain None);
  assert (List.equal (Option.equal String.equal) (domain (Some "valid")) [ Some "valid" ])
;;

let pagination_errors conn =
  let select (limit : int64 option) (offset : int64 option) : int32 list =
    let open! Stdlib in
    [%pgsql conn "SELECT id FROM people ORDER BY id LIMIT $?limit OFFSET $?offset"]
  in
  assert (List.equal Int32.equal (select None None) [ 1l; 2l ]);
  assert (List.is_empty (select (Some 0L) None));
  assert (List.is_empty (select None (Some Int64.max_value)));
  expect_sqlstate ~label:"negative limit" ~state:"2201W" (fun () ->
    select (Some (-1L)) None);
  expect_sqlstate ~label:"negative offset" ~state:"2201X" (fun () ->
    select None (Some (-1L)));
  let rows = select (Some Int64.max_value) (Some 1L) in
  assert (List.equal Int32.equal rows [ 2l ]);
  List.iter rows ~f:(fun id -> print_value "pagination after errors" (Int32.to_string id))
;;

let insert conn (id : int32) (name : string option) : unit =
  let open! Stdlib in
  [%pgsql conn "INSERT INTO ppx_items (tenant,id,name) VALUES (1,$id,$?name)"]
;;

let select conn : (int32 * string) list =
  let open! Stdlib in
  [%pgsql conn "SELECT id,name FROM ppx_items WHERE tenant=1 ORDER BY id"]
;;

let check_rows ~label conn expected =
  let rows = select conn in
  assert (
    List.equal (fun (a, b) (c, d) -> Int32.equal a c && String.equal b d) rows expected);
  List.iter rows ~f:(fun (id, name) ->
    print_value label (Int32.to_string id ^ ":" ^ name))
;;

let rollback conn observer =
  exec conn "TRUNCATE ppx_items RESTART IDENTITY";
  insert conn 1l (Some "committed");
  PGOCaml.begin_work conn;
  insert conn 2l (Some "uncommitted");
  check_rows ~label:"inside transaction" conn [ 1l, "committed"; 2l, "uncommitted" ];
  check_rows ~label:"observer before rollback" observer [ 1l, "committed" ];
  expect_sqlstate
    ~label:"unique violation"
    ~state:"23505"
    ~constraint_name:"ppx_items_pkey"
    ~table:"ppx_items"
    (fun () -> insert conn 1l (Some "duplicate"));
  expect_sqlstate ~label:"aborted transaction" ~state:"25P02" (fun () -> select conn);
  PGOCaml.rollback conn;
  check_rows ~label:"after rollback" conn [ 1l, "committed" ];
  check_rows ~label:"observer after rollback" observer [ 1l, "committed" ];
  PGOCaml.begin_work conn;
  insert conn 2l (Some "retried");
  check_rows ~label:"observer before commit" observer [ 1l, "committed" ];
  PGOCaml.commit conn;
  check_rows ~label:"observer after commit" observer [ 1l, "committed"; 2l, "retried" ]
;;

let savepoint conn observer =
  PGOCaml.begin_work conn;
  insert conn 3l (Some "before savepoint");
  exec conn "SAVEPOINT ppx_contract";
  insert conn 4l (Some "rolled back to savepoint");
  expect_sqlstate
    ~label:"not null violation"
    ~state:"23502"
    ~table:"ppx_items"
    ~column:"name"
    (fun () -> insert conn 5l None);
  exec conn "ROLLBACK TO SAVEPOINT ppx_contract";
  insert conn 4l (Some "after savepoint");
  exec conn "RELEASE SAVEPOINT ppx_contract";
  PGOCaml.commit conn;
  check_rows
    ~label:"observer after savepoint commit"
    observer
    [ 1l, "committed"; 2l, "retried"; 3l, "before savepoint"; 4l, "after savepoint" ]
;;

let exception_rollback conn observer =
  expect_sqlstate
    ~label:"transact exception"
    ~state:"23505"
    ~constraint_name:"ppx_items_pkey"
    (fun () ->
       PGOCaml.transact conn (fun conn ->
         insert conn 5l (Some "rolled back by transact");
         insert conn 1l (Some "duplicate")));
  let expected =
    [ 1l, "committed"; 2l, "retried"; 3l, "before savepoint"; 4l, "after savepoint" ]
  in
  check_rows ~label:"after transact rollback" conn expected;
  check_rows ~label:"observer after transact rollback" observer expected
;;

let () =
  with_connection (fun conn ->
    exec conn "SET TIME ZONE 'UTC'";
    PGOCaml.verbose := 0;
    List.iter
      [ integers
      ; floating_point
      ; text
      ; binary
      ; booleans
      ; numeric
      ; uuid
      ; temporal
      ; documents
      ; arrays
      ; domains
      ; enum_labels
      ; parameter_errors
      ; pagination_errors
      ]
      ~f:(fun test -> test conn);
    with_connection (fun observer ->
      Exn.protect
        ~finally:(fun () ->
          PGOCaml.rollback conn;
          exec conn "TRUNCATE ppx_items RESTART IDENTITY")
        ~f:(fun () ->
          rollback conn observer;
          savepoint conn observer;
          exception_rollback conn observer)))
;;
