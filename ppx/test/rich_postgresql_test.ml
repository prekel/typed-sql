open! Base

(* The same fixture is compiled by upstream, whose generated calls use Stdlib. *)
let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let setup conn =
  exec conn "TRUNCATE join_people, join_links";
  exec
    conn
    "INSERT INTO join_people VALUES (1, 'Ada', NULL), (2, 'Grace', 'note'), (3, 'Lin', NULL)";
  exec
    conn
    "INSERT INTO join_links VALUES (10, 1, 'first', true), (11, 1, NULL, false), (12, 2, 'second', true), (13, 99, 'orphan', true)"
;;

let outer conn : (int32 option * int32 option * string option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "nullable-results"
      "SELECT p.id, l.id, l.label FROM join_people p FULL OUTER JOIN join_links l ON p.id = l.person_id ORDER BY p.id NULLS LAST, l.id"]
;;

let right conn : (int32 option * int32 option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "nullable-results"
      "SELECT p.id, l.id FROM join_people p RIGHT JOIN join_links l ON p.id = l.person_id ORDER BY l.id"]
;;

let unmatched conn : int32 list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT l.id FROM join_people p LEFT JOIN join_links l ON p.id = l.person_id WHERE p.id = 3"]
;;

let using conn : (int32 option * string option * string option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "nullable-results"
      "SELECT id, p.name, l.label FROM join_people p FULL JOIN join_links l USING (id) ORDER BY id"]
;;

let natural conn : int32 list =
  let open! Stdlib in
  [%pgsql conn "SELECT id FROM join_people NATURAL LEFT JOIN join_links ORDER BY id"]
;;

let grouped_join conn : string list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT joined.name FROM (join_people p JOIN join_links l ON p.id = l.person_id) joined ORDER BY joined.person_id, joined.label NULLS LAST"]
;;

let arithmetic conn : (int32 option * int64 option * string option * string option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT id-1*2, CAST(id AS bigint), CASE WHEN id = 1 THEN name ELSE 'other' END AS display, COALESCE(note, 'none') FROM join_people ORDER BY id"]
;;

let casts conn (minimum : int64) : (string option * int32 option * bool option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT id::numeric(12,2), NULLIF(id, 2), id::bigint >= $minimum FROM join_people ORDER BY id"]
;;

let global_aggregates conn
  : (int64 option
    * int64 option
    * string option
    * string option
    * bool option
    * int32 option list option)
      list
  =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT count(*), sum(id), avg(id), min(label), bool_and(active), array_agg(id ORDER BY id DESC) FROM join_links"]
;;

let filtered conn (separator : string) : (int64 option * string option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT count(DISTINCT person_id) FILTER (WHERE active), string_agg(label, $separator ORDER BY id) FROM join_links"]
;;

let grouped conn (minimum : int64) : (string * int64 option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT p.name, count(l.id) AS n FROM join_people p LEFT JOIN join_links l ON p.id = l.person_id GROUP BY p.name HAVING count(l.id) >= $minimum ORDER BY n DESC, p.name"]
;;

let union conn (limit : int64) : int64 option list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT NULL AS n UNION ALL SELECT id::bigint FROM join_people UNION SELECT 1::bigint ORDER BY n NULLS LAST LIMIT $limit"]
;;

let sets conn : int32 option list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT id FROM join_people UNION SELECT person_id FROM join_links INTERSECT SELECT id FROM join_people EXCEPT SELECT 2 ORDER BY id"]
;;

let correlated conn : (string * int64 option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT p.name, (SELECT count(*) FROM join_links l WHERE l.person_id = p.id) AS n FROM join_people p WHERE EXISTS (SELECT id FROM join_links l WHERE l.person_id = p.id) ORDER BY p.id"]
;;

let subqueries conn : int32 list =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT id FROM join_people WHERE id IN (SELECT person_id FROM join_links) AND id = ANY(SELECT person_id FROM join_links WHERE active) AND id <> ALL(SELECT person_id FROM join_links WHERE NOT active) ORDER BY id"]
;;

let derived conn (increment : int32) : int32 option list =
  let open! Stdlib in
  [%pgsql
    conn "SELECT q.n FROM (SELECT id + $increment AS n FROM join_people) q ORDER BY q.n"]
;;

let ctes conn (minimum : int32) : int32 list =
  let open! Stdlib in
  [%pgsql
    conn
      "WITH first AS MATERIALIZED (SELECT id FROM join_people WHERE id >= $minimum), second(n) AS NOT MATERIALIZED (SELECT id FROM first) SELECT n FROM second ORDER BY n"]
;;

let recursive conn (maximum : int32) : int32 option list =
  let open! Stdlib in
  [%pgsql
    conn
      "WITH RECURSIVE t(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM t WHERE n < $maximum) SELECT n FROM t ORDER BY n"]
;;

let update_cte conn (id : int32) (suffix : string) : (int32 * string option) list =
  let open! Stdlib in
  [%pgsql
    conn
      "WITH changed AS (UPDATE join_people SET name = name || $suffix WHERE id = $id RETURNING id, name || '!') SELECT * FROM changed"]
;;

let delete_cte conn (id : int32) : int32 list =
  let open! Stdlib in
  [%pgsql
    conn
      "WITH gone AS (DELETE FROM join_links WHERE id = $id) SELECT id FROM join_people ORDER BY id"]
;;

let insert_cte conn (id : int32) : int32 list =
  let open! Stdlib in
  [%pgsql
    conn
      "WITH moved AS (DELETE FROM join_people WHERE id = $id RETURNING id, name, note) INSERT INTO join_people SELECT id+100, name, note FROM moved RETURNING id"]
;;

let insert_expression conn (id : int32) (name : string) : int32 option list =
  let open! Stdlib in
  [%pgsql
    conn
      "INSERT INTO join_people (id, name) VALUES ($id+1000, $name || '!') RETURNING id+1"]
;;

let command conn (id : int32) : unit =
  let open! Stdlib in
  [%pgsql
    conn
      "WITH gone AS (DELETE FROM join_links WHERE id = $id RETURNING person_id) DELETE FROM join_people WHERE id IN (SELECT person_id FROM gone)"]
;;

let type_edges conn (id : int32) (selector : int32)
  : (string option * int64 option * bool option) list
  =
  let open! Stdlib in
  [%pgsql
    conn
      "SELECT NULLIF(id, 2.2), COALESCE($id, id)::bigint, CASE $selector::integer WHEN id THEN true ELSE false END FROM join_people ORDER BY id"]
;;

let bytes conn (delimiter : string) : string option list =
  let open! Stdlib in
  [%pgsql conn "SELECT string_agg(data, $delimiter ORDER BY id) FROM people"]
;;

let parenthesized conn (minimum : int32) (inner : int64) (other : int64) (outer : int64)
  : int32 option list
  =
  let open! Stdlib in
  [%pgsql
    conn
      "(SELECT id FROM join_people WHERE id > $minimum ORDER BY id LIMIT $inner) UNION ALL (SELECT id FROM join_people ORDER BY id LIMIT $other) LIMIT $outer"]
;;

let output_names conn =
  let open! Stdlib in
  [%pgsql.object
    conn
      "SELECT 1::bigint, CASE WHEN true THEN name ELSE name END, (SELECT count(*) FROM join_links) FROM join_people ORDER BY id LIMIT 1"]
;;

let recursive_parenthesized conn (maximum : int32) : int32 option list =
  let open! Stdlib in
  [%pgsql
    conn
      "WITH RECURSIVE t(n) AS (SELECT 1 UNION (SELECT n+1 FROM t WHERE n < $maximum)) SELECT n FROM t ORDER BY n"]
;;

type t =
  { name : string
  ; count : int64 option
  }

let t_of_pgocaml row = { name = row#name; count = row#count }

let objects conn =
  let rows =
    let open! Stdlib in
    [%pgsql.object
      conn
        "SELECT p.name, count(l.id) AS count FROM join_people p LEFT JOIN join_links l ON p.id = l.person_id GROUP BY p.name ORDER BY p.name"]
  in
  List.map rows ~f:t_of_pgocaml
;;

let print_value value = Stdlib.print_endline value

let print_i32 = function
  | None -> print_value "NULL"
  | Some value -> print_value (Int32.to_string value)
;;

let check_int32 left right = assert (List.equal (Option.equal Int32.equal) left right)

let check_joins conn =
  let rows = outer conn in
  assert (Int.equal (List.length rows) 5);
  let last = List.last_exn rows in
  let person, link, label = last in
  assert (
    Option.is_none person
    && Option.equal Int32.equal link (Some 13l)
    && Option.equal String.equal label (Some "orphan"));
  assert (Int.equal (List.length (right conn)) 4);
  (match Result.try_with (fun () -> unmatched conn) with
   | Error (Failure message) -> print_value message
   | _ -> failwith "outer JOIN must preserve the upstream non-null heuristic failure");
  let rows = using conn in
  assert (Int.equal (List.length rows) 7);
  List.iter rows ~f:(fun (id, _, _) -> print_i32 id);
  assert (List.equal Int32.equal (natural conn) [ 1l; 2l; 3l ]);
  assert (List.equal String.equal (grouped_join conn) [ "Ada"; "Ada"; "Grace" ])
;;

let check_expressions conn =
  let rows = arithmetic conn in
  List.iter rows ~f:(fun (id, big, display, note) ->
    print_i32 id;
    print_value (Option.value_map big ~default:"NULL" ~f:Int64.to_string);
    print_value (Option.value display ~default:"NULL");
    print_value (Option.value note ~default:"NULL"));
  let rows = casts conn 2L in
  assert (Int.equal (List.length rows) 3);
  List.iter rows ~f:(fun (amount, id, enough) ->
    print_value (Option.value amount ~default:"NULL");
    print_i32 id;
    print_value (Option.value_map enough ~default:"NULL" ~f:Bool.to_string))
;;

let check_aggregates conn =
  let count, total, average, minimum, all_active, ids =
    List.hd_exn (global_aggregates conn)
  in
  assert (
    Option.equal Int64.equal count (Some 4L) && Option.equal Int64.equal total (Some 46L));
  print_value (Option.value average ~default:"NULL");
  print_value (Option.value minimum ~default:"NULL");
  assert (Option.equal Bool.equal all_active (Some false));
  assert (
    Option.equal
      (List.equal (Option.equal Int32.equal))
      ids
      (Some [ Some 13l; Some 12l; Some 11l; Some 10l ]));
  let count, labels = List.hd_exn (filtered conn ",") in
  assert (Option.equal Int64.equal count (Some 3L));
  assert (Option.equal String.equal labels (Some "first,second,orphan"));
  let rows = grouped conn 1L in
  assert (
    List.equal
      (fun (a, b) (x, y) -> String.equal a x && Option.equal Int64.equal b y)
      rows
      [ "Ada", Some 2L; "Grace", Some 1L ]);
  List.iter (objects conn) ~f:(fun row ->
    Stdlib.Printf.printf
      "%s:%s\n"
      row.name
      (Option.value_map row.count ~default:"NULL" ~f:Int64.to_string))
;;

let check_queries conn =
  assert (
    List.equal
      (Option.equal Int64.equal)
      (union conn 4L)
      [ Some 1L; Some 2L; Some 3L; None ]);
  check_int32 (sets conn) [ Some 1l; Some 3l ];
  assert (
    List.equal
      (fun (a, b) (x, y) -> String.equal a x && Option.equal Int64.equal b y)
      (correlated conn)
      [ "Ada", Some 2L; "Grace", Some 1L ]);
  assert (List.equal Int32.equal (subqueries conn) [ 2l ]);
  check_int32 (derived conn 10l) [ Some 11l; Some 12l; Some 13l ];
  assert (List.equal Int32.equal (ctes conn 2l) [ 2l; 3l ]);
  check_int32 (recursive conn 4l) [ Some 1l; Some 2l; Some 3l; Some 4l ];
  check_int32 (recursive conn 2l) [ Some 1l; Some 2l ]
;;

let check_types conn =
  List.iter (type_edges conn 8l 2l) ~f:(fun (numeric, wide, selected) ->
    print_value (Option.value numeric ~default:"NULL");
    assert (Option.equal Int64.equal wide (Some 8L));
    print_value (Option.value_map selected ~default:"NULL" ~f:Bool.to_string));
  assert (
    List.equal (Option.equal String.equal) (bytes conn "|") [ Some "\000\255|\000\255" ]);
  check_int32 (parenthesized conn 1l 1L 1L 2L) [ Some 2l; Some 1l ];
  let row = List.hd_exn (output_names conn) in
  assert (Option.equal Int64.equal row#int8 (Some 1L));
  assert (Option.equal String.equal row#name (Some "Ada"));
  assert (Option.equal Int64.equal row#count (Some 4L));
  check_int32 (recursive_parenthesized conn 3l) [ Some 1l; Some 2l; Some 3l ]
;;

let rec check_dml conn =
  let rows = update_cte conn 1l "+" in
  assert (
    List.equal
      (fun (a, b) (x, y) -> Int32.equal a x && Option.equal String.equal b y)
      rows
      [ 1l, Some "Ada+!" ]);
  ignore (delete_cte conn 13l : int32 list);
  assert (List.equal Int32.equal (scalar_count_orphan conn) []);
  assert (List.equal Int32.equal (insert_cte conn 3l) [ 103l ]);
  check_int32 (insert_expression conn 4l "New") [ Some 1005l ];
  command conn 12l

and scalar_count_orphan conn =
  let open! Stdlib in
  [%pgsql conn "SELECT id FROM join_links WHERE id = 13"]
;;

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      setup conn;
      check_joins conn;
      check_expressions conn;
      check_aggregates conn;
      check_queries conn;
      check_types conn;
      check_dml conn)
;;
