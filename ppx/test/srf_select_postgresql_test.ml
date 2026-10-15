open! Base

let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let show encode = Option.value_map ~default:"NULL" ~f:encode
let equal_ints = List.equal (Option.equal Int32.equal)

let print_ints label rows =
  List.iter rows ~f:(fun value ->
    Stdlib.Printf.printf "%s:%s\n" label (show Int32.to_string value))
;;

let select_array conn =
  let query (values : int32 option list option) : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT unnest($?values::int[])"]
  in
  assert (List.is_empty (query None));
  assert (List.is_empty (query (Some [])));
  let values = [ Some 1l; None; Some 3l ] in
  let rows = query (Some values) in
  assert (equal_ints rows values);
  print_ints "select unnest" rows
;;

let lockstep conn =
  let values = [ Some "a" ] in
  let rows : (int32 option * string option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT generate_series(1,3) AS id,unnest($values::text[]) AS label ORDER BY id"]
  in
  assert (
    List.equal
      (fun (a, b) (c, d) -> Option.equal Int32.equal a c && Option.equal String.equal b d)
      rows
      [ Some 1l, Some "a"; Some 2l, None; Some 3l, None ]);
  List.iter rows ~f:(fun (id, label) ->
    Stdlib.Printf.printf "lockstep:%s:%S\n" (show Int32.to_string id) (show Fn.id label));
  let empty = [] in
  let rows : (int32 option * int32 option) list =
    let open! Stdlib in
    [%pgsql conn "SELECT generate_series(1,2) AS id,unnest($empty::int[]) ORDER BY id"]
  in
  assert (
    List.equal
      (fun (a, b) (c, d) -> Option.equal Int32.equal a c && Option.equal Int32.equal b d)
      rows
      [ Some 1l, None; Some 2l, None ])
;;

module Row = struct
  type t =
    { id : int32
    ; name : string
    ; n : int32 option
    ; label : string option
    }

  let of_pgocaml row = { id = row#id; name = row#name; n = row#n; label = row#label }
end

let correlated_objects conn =
  let labels = [ Some "x"; None ] in
  let rows =
    let open! Stdlib in
    [%pgsql.object
      conn
        "SELECT k.id,k.name,generate_series(1,k.id) AS n,unnest($labels::text[]) AS label FROM group_keys k ORDER BY k.id,n NULLS LAST"]
  in
  let rows = List.map rows ~f:Row.of_pgocaml in
  assert (Int.equal (List.length rows) 4);
  List.iter rows ~f:(fun (row : Row.t) ->
    Stdlib.Printf.printf
      "object:%ld:%s:%s:%S\n"
      row.id
      row.name
      (show Int32.to_string row.n)
      (show Fn.id row.label));
  let empty = [] in
  let rows : (int32 * int32 option) list =
    let open! Stdlib in
    [%pgsql conn "SELECT id,unnest($empty::int[]) FROM group_keys"]
  in
  assert (List.is_empty rows)
;;

let nested conn =
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT generate_series(1,generate_series(1,3)) AS n ORDER BY n"]
  in
  assert (equal_ints rows [ Some 1l; Some 1l; Some 1l; Some 2l; Some 2l; Some 3l ]);
  print_ints "nested" rows;
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT abs(generate_series(-1,1))+10 AS n ORDER BY n"]
  in
  assert (equal_ints rows [ Some 10l; Some 11l; Some 11l ]);
  print_ints "wrapper" rows;
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT nullif(generate_series(1,3),2) AS n ORDER BY n NULLS LAST"]
  in
  assert (equal_ints rows [ Some 1l; Some 3l; None ]);
  print_ints "nullif" rows
;;

let boolean_outputs conn =
  let rows : bool option list =
    let open! Stdlib in
    [%pgsql conn "SELECT generate_series(1,3) IN(1,3)"]
  in
  assert (List.equal (Option.equal Bool.equal) rows [ Some true; Some false; Some true ]);
  List.iter rows ~f:(fun v -> Stdlib.Printf.printf "in:%s\n" (show Bool.to_string v));
  let ids = [ Some 1l; Some 3l ] in
  let rows : bool option list =
    let open! Stdlib in
    [%pgsql conn "SELECT generate_series(1,3)=ANY($ids::int[])"]
  in
  assert (List.equal (Option.equal Bool.equal) rows [ Some true; Some false; Some true ])
;;

let grouped conn =
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT unnest(array_agg(id ORDER BY id)) FROM group_keys"]
  in
  assert (equal_ints rows [ Some 1l; Some 2l ]);
  print_ints "aggregate before SRF" rows;
  let rows : (int32 option * int64 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT generate_series(1,3) AS n,count(*) FROM group_keys GROUP BY n ORDER BY n"]
  in
  List.iter rows ~f:(fun (n, count) ->
    assert (Option.equal Int64.equal count (Some 2L));
    Stdlib.Printf.printf
      "group:%s:%s\n"
      (show Int32.to_string n)
      (show Int64.to_string count))
;;

let windows conn =
  let rows : (int32 * int32 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT id,generate_series(1,row_number() OVER(ORDER BY id)::int) AS n FROM group_keys ORDER BY id,n"]
  in
  assert (Int.equal (List.length rows) 3);
  List.iter rows ~f:(fun (id, n) ->
    Stdlib.Printf.printf "window:%ld:%s\n" id (show Int32.to_string n))
;;

let ordering conn =
  let rows : int32 list =
    let open! Stdlib in
    [%pgsql conn "SELECT id FROM group_keys ORDER BY generate_series(1,2),id"]
  in
  assert (List.equal Int32.equal rows [ 1l; 2l; 1l; 2l ]);
  List.iter rows ~f:(fun id -> Stdlib.Printf.printf "hidden order:%ld\n" id);
  let limit = 2L
  and offset = 1L in
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql
      conn "SELECT generate_series(1,5) AS n ORDER BY n LIMIT $limit OFFSET $offset"]
  in
  assert (equal_ints rows [ Some 2l; Some 3l ]);
  print_ints "pagination" rows;
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql
      conn
        "WITH q AS(SELECT generate_series(1,2) AS n) SELECT n FROM q UNION ALL SELECT generate_series(3,3) ORDER BY n"]
  in
  assert (equal_ints rows [ Some 1l; Some 2l; Some 3l ]);
  print_ints "CTE union" rows
;;

let rows_from conn =
  let ids = [ Some 10l; None; Some 30l ] in
  let rows =
    let open! Stdlib in
    [%pgsql.object
      conn
        "SELECT * FROM ROWS FROM(unnest($ids::int[]),generate_series(1::bigint,2)) WITH ORDINALITY q(id,value,n) ORDER BY n"]
  in
  assert (Int.equal (List.length rows) 3);
  List.iteri rows ~f:(fun index row ->
    assert (Option.equal Int64.equal row#n (Some (Int64.of_int (index + 1))));
    Stdlib.Printf.printf
      "rows:%s:%s:%s\n"
      (show Int32.to_string row#id)
      (show Int64.to_string row#value)
      (show Int64.to_string row#n));
  let labels = [ Some "a" ] in
  let rows : (int32 option * string option * int32 option * int64 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT * FROM ROWS FROM(unnest($ids::int[],$labels::text[]),generate_series(1,4)) WITH ORDINALITY q(id,label,value,n) ORDER BY n"]
  in
  assert (Int.equal (List.length rows) 4);
  List.iter rows ~f:(fun (id, label, value, n) ->
    Stdlib.Printf.printf
      "multi rows:%s:%S:%s:%s\n"
      (show Int32.to_string id)
      (show Fn.id label)
      (show Int32.to_string value)
      (show Int64.to_string n));
  let rows : (int32 option * int32 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT generate_series.generate_series,generate_series.unnest FROM ROWS FROM(generate_series(1,2),unnest($ids::int[]))"]
  in
  assert (Int.equal (List.length rows) 3)
;;

let rows_from_scalar conn =
  let label = "LABEL" in
  let rows : (string option * int32 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT * FROM ROWS FROM(lower($label),generate_series(1,2)) q(label,n) ORDER BY n"]
  in
  assert (
    List.equal
      (fun (a, b) (c, d) -> Option.equal String.equal a c && Option.equal Int32.equal b d)
      rows
      [ Some "label", Some 1l; None, Some 2l ]);
  List.iter rows ~f:(fun (label, n) ->
    Stdlib.Printf.printf "scalar rows:%S:%s\n" (show Fn.id label) (show Int32.to_string n));
  let rows : int32 option list =
    let open! Stdlib in
    [%pgsql conn "SELECT q.q FROM ROWS FROM(generate_series(1,2)) q"]
  in
  assert (equal_ints rows [ Some 1l; Some 2l ])
;;

let rows_from_lateral conn =
  let ids = [] in
  let rows : (int32 * int32 option * int32 option * int64 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT k.id,q.* FROM group_keys k LEFT JOIN LATERAL ROWS FROM(generate_series(1,k.id),unnest($ids::int[])) WITH ORDINALITY q(value,unused,n) ON true ORDER BY k.id,q.n"]
  in
  assert (Int.equal (List.length rows) 3);
  List.iter rows ~f:(fun (id, value, unused, n) ->
    assert (Option.is_none unused);
    Stdlib.Printf.printf
      "lateral rows:%ld:%s:%s\n"
      id
      (show Int32.to_string value)
      (show Int64.to_string n));
  let rows : (int32 * int32 option * int64 option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT k.id,q.* FROM group_keys k LEFT JOIN ROWS FROM(generate_series(1,0)) WITH ORDINALITY q(value,n) ON true ORDER BY k.id"]
  in
  assert (
    List.for_all rows ~f:(fun (_, value, n) -> Option.is_none value && Option.is_none n))
;;

let dml conn =
  PGOCaml.begin_work conn;
  Exn.protect
    ~finally:(fun () -> PGOCaml.rollback conn)
    ~f:(fun () ->
      let inserted : int32 list =
        let open! Stdlib in
        [%pgsql
          conn
            "INSERT INTO group_keys(tenant,id,name) SELECT 1,generate_series(10,11),'inserted' RETURNING id"]
      in
      assert (List.equal Int32.equal inserted [ 10l; 11l ]);
      List.iter inserted ~f:(fun id -> Stdlib.Printf.printf "inserted:%ld\n" id);
      let deleted : int32 list =
        let open! Stdlib in
        [%pgsql
          conn
            "DELETE FROM group_keys USING ROWS FROM(generate_series(10,10)) q(id) WHERE group_keys.id=q.id RETURNING group_keys.id"]
      in
      assert (List.equal Int32.equal deleted [ 10l ]))
;;

let invalid_contexts conn =
  List.iter
    [ "WHERE", "0A000", "SELECT id FROM group_keys WHERE generate_series(1,3)=id"
    ; "CASE", "0A000", "SELECT CASE WHEN true THEN generate_series(1,3) END"
    ; "COALESCE", "0A000", "SELECT coalesce(generate_series(1,3),0)"
    ; "aggregate", "0A000", "SELECT sum(generate_series(1,3))"
    ; "window", "0A000", "SELECT first_value(generate_series(1,3)) OVER()"
    ; ( "FROM"
      , "0A000"
      , "SELECT * FROM ROWS FROM(generate_series(1,generate_series(1,3))) q" )
    ; "boolean", "42804", "SELECT generate_series(1,3)>0 AND true"
    ; "RETURNING", "0A000", "DELETE FROM group_keys RETURNING generate_series(1,3)"
    ]
    ~f:(fun (label, state, query) ->
      match PGOCaml.prepare conn ~query () with
      | () -> failwith ("PostgreSQL accepted an invalid SRF context: " ^ label)
      | exception PGOCaml.PostgreSQL_Error (_, fields) ->
        let code = List.Assoc.find_exn fields 'C' ~equal:Char.equal in
        assert (String.equal code state);
        Stdlib.Printf.printf "invalid %s:%s\n" label code)
;;

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      PGOCaml.verbose := 0;
      exec conn "SET TIME ZONE 'UTC'";
      List.iter
        [ select_array
        ; lockstep
        ; correlated_objects
        ; nested
        ; boolean_outputs
        ; grouped
        ; windows
        ; ordering
        ; rows_from
        ; rows_from_scalar
        ; rows_from_lateral
        ; dml
        ; invalid_contexts
        ]
        ~f:(fun test -> test conn))
;;
