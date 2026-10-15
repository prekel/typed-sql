open! Base

let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let print_values label encode rows =
  List.iter rows ~f:(fun value ->
    Stdlib.Printf.printf
      "%s:%S\n"
      label
      (Option.value_map value ~default:"NULL" ~f:encode))
;;

let integers conn =
  let stop = 5l
  and step = 2l in
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT g FROM generate_series(1,$stop,$step) g ORDER BY g"]
  in
  assert (List.equal (Option.equal Int32.equal) rows [ Some 1l; Some 3l; Some 5l ]);
  print_values "int series" Int32.to_string rows;
  let stop = 1L
  and step = -2L in
  let rows : int64 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT g FROM generate_series(5::bigint,$stop,$step) g ORDER BY g DESC"]
  in
  assert (List.equal (Option.equal Int64.equal) rows [ Some 5L; Some 3L; Some 1L ]);
  print_values "bigint series" Int64.to_string rows;
  let stop = "2.0"
  and step = "0.5" in
  let rows : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT g FROM generate_series(1.0,$stop,$step) g ORDER BY g"]
  in
  assert (
    List.equal (Option.equal String.equal) rows [ Some "1.0"; Some "1.5"; Some "2.0" ]);
  print_values "numeric series" Fn.id rows
;;

let series_edges conn =
  let series start stop step : int32 option list =
    let open! Stdlib in
    [%pgsql
      conn "SELECT g FROM generate_series($?start::integer,$?stop,$?step) g ORDER BY g"]
  in
  assert (List.is_empty (series None (Some 3l) (Some 1l)));
  assert (List.is_empty (series (Some 1l) None (Some 1l)));
  assert (List.is_empty (series (Some 1l) (Some 3l) None));
  assert (List.is_empty (series (Some 3l) (Some 1l) (Some 1l)));
  assert (List.is_empty (series (Some 1l) (Some 3l) (Some (-1l))));
  (match series (Some 1l) (Some 3l) (Some 0l) with
   | _ -> failwith "zero step accepted"
   | exception PGOCaml.PostgreSQL_Error (_, fields) ->
     let code = List.Assoc.find_exn fields 'C' ~equal:Char.equal in
     assert (String.equal code "22023");
     Stdlib.print_endline code);
  let rows = series (Some Int32.max_value) (Some Int32.max_value) (Some 1l) in
  assert (List.equal (Option.equal Int32.equal) rows [ Some Int32.max_value ]);
  print_values "series after error" Int32.to_string rows
;;

let temporal conn =
  let start = PGOCaml.timestamp_of_string "2000-02-28 00:00:00" in
  let stop = PGOCaml.timestamp_of_string "2000-03-01 00:00:00" in
  let step = PGOCaml.interval_of_string "1 day" in
  let rows =
    let open! Stdlib in
    [%pgsql
      conn "SELECT g FROM generate_series($start::timestamp,$stop,$step) g ORDER BY g"]
  in
  assert (Int.equal (List.length rows) 3);
  print_values "timestamp series" PGOCaml.string_of_timestamp rows;
  let start = PGOCaml.timestamptz_of_string "2000-02-28 00:00:00+00" in
  let stop = PGOCaml.timestamptz_of_string "2000-03-01 00:00:00+00" in
  let rows =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT g FROM pg_catalog.generate_series($start::timestamptz,$stop,$step) g ORDER BY g"]
  in
  assert (Int.equal (List.length rows) 3);
  print_values "timestamptz series" PGOCaml.string_of_timestamptz rows
;;

let arrays conn =
  let select (values : int32 option list option) : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT u FROM unnest($?values::integer[]) u"]
  in
  assert (List.is_empty (select None));
  assert (List.is_empty (select (Some [])));
  let values = [ Some 1l; None; Some 3l ] in
  let rows = select (Some values) in
  assert (List.equal (Option.equal Int32.equal) rows values);
  print_values "unnest" Int32.to_string rows;
  let names = [ Some "NULL"; None ] in
  let rows =
    let open! Stdlib in
    [%pgsql.object
      conn
        "SELECT * FROM unnest($values::int[],$names::text[]) WITH ORDINALITY AS u(id,name,n) ORDER BY n"]
  in
  assert (Int.equal (List.length rows) 3);
  List.iteri rows ~f:(fun index row ->
    assert (Option.equal Int64.equal row#n (Some (Int64.of_int (index + 1))));
    Stdlib.Printf.printf
      "multi:%s:%S:%s\n"
      (Option.value_map row#id ~default:"NULL" ~f:Int32.to_string)
      (Option.value row#name ~default:"NULL")
      (Option.value_map row#n ~default:"NULL" ~f:Int64.to_string))
;;

let array_functions conn =
  let query values delimiter replacement dimension =
    let open! Stdlib in
    [%pgsql.object
      conn
        "SELECT cardinality($?values::int[]) AS size,array_length($?values::int[],$dimension) AS length,array_to_string($?values::int[],$?delimiter,$?replacement) AS display"]
  in
  List.iter
    [ None; Some []; Some [ Some 1l; None; Some 3l ] ]
    ~f:(fun values ->
      List.iter [ 1l; 2l ] ~f:(fun dimension ->
        List.iter [ None; Some "," ] ~f:(fun delimiter ->
          List.iter [ None; Some "missing" ] ~f:(fun replacement ->
            let row = List.hd_exn (query values delimiter replacement dimension) in
            let expected_size =
              Option.map values ~f:(fun values -> Int32.of_int_exn (List.length values))
            in
            assert (Option.equal Int32.equal row#size expected_size);
            if
              Int32.equal dimension 2l
              || Option.value_map expected_size ~default:true ~f:(Int32.equal 0l)
            then
              assert (Option.is_none row#length);
            Stdlib.Printf.printf
              "arrays:%s:%s:%S\n"
              (Option.value_map row#size ~default:"NULL" ~f:Int32.to_string)
              (Option.value_map row#length ~default:"NULL" ~f:Int32.to_string)
              (Option.value row#display ~default:"NULL")))));
  let values = [ Some "a"; None; Some "b" ] in
  let rows : string option list =
    let open! Stdlib in
    [%pgsql conn "SELECT array_to_string($values::text[],'|')"]
  in
  assert (List.equal (Option.equal String.equal) rows [ Some "a|b" ]);
  print_values "two argument array_to_string" Fn.id rows
;;

let lateral conn =
  let rows : (int32 * int32 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT k.id,g FROM group_keys k CROSS JOIN generate_series(1,k.id) g ORDER BY k.id,g"]
  in
  assert (Int.equal (List.length rows) 3);
  List.iter rows ~f:(fun (id, g) ->
    Stdlib.Printf.printf
      "lateral:%ld:%s\n"
      id
      (Option.value_map g ~default:"NULL" ~f:Int32.to_string));
  let rows : (int32 * int32 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT k.id,g FROM group_keys k LEFT JOIN LATERAL generate_series(1,0) g ON true ORDER BY k.id"]
  in
  assert (List.for_all rows ~f:(fun (_, g) -> Option.is_none g))
;;

let grouping conn =
  let rows : (int32 * int32 * string * int64 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT k.*,count(*) FROM group_keys k GROUP BY k.tenant,k.id HAVING k.name<>'' ORDER BY k.name"]
  in
  List.iter rows ~f:(fun (tenant, id, name, count) ->
    assert (Option.equal Int64.equal count (Some 1L));
    Stdlib.Printf.printf "group:%ld:%ld:%s\n" tenant id name);
  let rows : (string * string) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT a.name,b.name FROM group_keys a JOIN group_keys b ON a.id=b.id GROUP BY a.tenant,a.id,b.tenant,b.id ORDER BY a.name,b.name"]
  in
  assert (
    List.equal
      (fun (a, b) (c, d) -> String.equal a c && String.equal b d)
      rows
      [ "Ada", "Ada"; "Grace", "Grace" ]);
  List.iter rows ~f:(fun (a, b) -> Stdlib.Printf.printf "self:%s:%s\n" a b)
;;

let grouping_windows conn =
  let rows : (string * int64 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT name,count(*) OVER(ORDER BY name) FROM group_keys GROUP BY tenant,id ORDER BY name"]
  in
  List.iter rows ~f:(fun (name, count) ->
    Stdlib.Printf.printf
      "group window:%s:%s\n"
      name
      (Option.value_map count ~default:"NULL" ~f:Int64.to_string));
  let rows : string option list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT (SELECT k.name) FROM group_keys k GROUP BY k.tenant,k.id ORDER BY k.name"]
  in
  assert (List.equal (Option.equal String.equal) rows [ Some "Ada"; Some "Grace" ]);
  print_values "group outer reference" Fn.id rows
;;

let grouping_errors conn =
  List.iter
    [ "partial PK", "SELECT name FROM group_keys GROUP BY id"
    ; "deferrable PK", "SELECT name FROM deferrable_group_keys GROUP BY tenant,id"
    ; "unique column", "SELECT id FROM ppx_items GROUP BY name"
    ; "derived PK", "SELECT name FROM (SELECT * FROM group_keys) k GROUP BY tenant,id"
    ; ( "CTE PK"
      , "WITH k AS (SELECT * FROM group_keys) SELECT name FROM k GROUP BY tenant,id" )
    ]
    ~f:(fun (label, query) ->
      match PGOCaml.prepare conn ~query () with
      | () -> failwith (label ^ ": PostgreSQL accepted an unproved grouping dependency")
      | exception PGOCaml.PostgreSQL_Error (_, fields) ->
        let code = List.Assoc.find_exn fields 'C' ~equal:Char.equal in
        assert (String.equal code "42803");
        Stdlib.Printf.printf "%s:%s\n" label code)
;;

let dml conn =
  PGOCaml.begin_work conn;
  Exn.protect
    ~finally:(fun () -> PGOCaml.rollback conn)
    ~f:(fun () ->
      let updated : int32 list =
        let open! Stdlib in
        [%pgsql
          conn
            "UPDATE group_keys SET name='updated' FROM generate_series(1,1) g WHERE id=g RETURNING id"]
      in
      assert (List.equal Int32.equal updated [ 1l ]);
      List.iter updated ~f:(fun id -> Stdlib.Printf.printf "updated:%ld\n" id);
      let deleted : int32 list =
        let open! Stdlib in
        [%pgsql
          conn
            "DELETE FROM group_keys USING generate_series(2,2) g WHERE id=g RETURNING id"]
      in
      assert (List.equal Int32.equal deleted [ 2l ]);
      List.iter deleted ~f:(fun id -> Stdlib.Printf.printf "deleted:%ld\n" id))
;;

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      PGOCaml.verbose := 0;
      exec conn "SET TIME ZONE 'UTC'";
      exec
        conn
        "CREATE TABLE IF NOT EXISTS group_keys(tenant integer NOT NULL,id integer NOT NULL,name text NOT NULL,PRIMARY KEY(tenant,id))";
      exec
        conn
        "CREATE TABLE IF NOT EXISTS deferrable_group_keys(tenant integer NOT NULL,id integer NOT NULL,name text NOT NULL,PRIMARY KEY(tenant,id) DEFERRABLE INITIALLY IMMEDIATE)";
      exec conn "TRUNCATE group_keys,deferrable_group_keys";
      exec conn "INSERT INTO group_keys VALUES (1,1,'Ada'),(1,2,'Grace')";
      List.iter
        [ integers
        ; series_edges
        ; temporal
        ; arrays
        ; array_functions
        ; lateral
        ; grouping
        ; grouping_windows
        ; grouping_errors
        ; dml
        ]
        ~f:(fun f -> f conn))
;;
