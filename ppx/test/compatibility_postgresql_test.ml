open! Base

let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let strings rows =
  List.iter rows ~f:(fun value ->
    Stdlib.print_endline (Option.value value ~default:"NULL"))
;;

let integers rows = strings (List.map rows ~f:(Option.map ~f:Int32.to_string))
let bigints rows = strings (List.map rows ~f:(Option.map ~f:Int64.to_string))

let casts conn =
  let arrays : (string option list * string option list option) list =
    let open! Stdlib in
    [%pgsql
      conn "SELECT vs::varchar(10)[],vs::varchar(20)[] FROM typmod_values ORDER BY id"]
  in
  List.iter arrays ~f:(fun (same, changed) ->
    assert (Option.equal (List.equal (Option.equal String.equal)) changed (Some same)));
  let direct : string list =
    let open! Stdlib in
    [%pgsql
      conn
        "WITH source AS(SELECT v FROM typmod_values) SELECT v::varchar(10) FROM source ORDER BY v"]
  in
  List.iter direct ~f:Stdlib.print_endline;
  let rows : (string * string * string * string option * string option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT v::varchar(10),c::char(3),n::numeric(8,2),v::varchar(20),n::numeric FROM typmod_values ORDER BY id"]
  in
  List.iter rows ~f:(fun (v, c, n, wide, plain) ->
    assert (Option.equal String.equal wide (Some v));
    assert (Option.equal String.equal plain (Some n));
    Stdlib.Printf.printf "%s:%s:%s\n" v c n);
  let rows =
    let open! Stdlib in
    [%pgsql.object
      conn
        "SELECT t::timestamp(3) AS same,t::timestamp AS changed,z::timestamptz(3) AS zoned,tm::time(3) AS clock,i::interval day to second(3) AS duration,i::interval(3) AS changed_duration FROM typmod_values ORDER BY id"]
  in
  List.iter rows ~f:(fun row ->
    let same = PGOCaml.string_of_timestamp row#same in
    assert (
      Option.equal
        String.equal
        (Option.map row#changed ~f:PGOCaml.string_of_timestamp)
        (Some same));
    ignore (PGOCaml.string_of_timestamptz row#zoned : string);
    ignore (PGOCaml.string_of_time row#clock : string);
    assert (
      Option.equal
        String.equal
        (Option.map row#changed_duration ~f:PGOCaml.string_of_interval)
        (Some (PGOCaml.string_of_interval row#duration)));
    Stdlib.print_endline same)
;;

let functions conn =
  let replacement = "X" in
  strings
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT lower(v)||upper(v)||replace(v,'a',$replacement)||trim(both 'a' from v) FROM typmod_values ORDER BY id"]);
  integers
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT length(v)+char_length(v)+octet_length(v) FROM typmod_values ORDER BY id"]);
  strings
    (let open! Stdlib in
     [%pgsql conn "SELECT substring(v FROM 1 FOR 2) FROM typmod_values ORDER BY id"]);
  strings
    (let open! Stdlib in
     [%pgsql conn "SELECT concat(v,id) FROM typmod_values ORDER BY id"]);
  let rounded : float option list =
    let open! Stdlib in
    [%pgsql conn "SELECT round(id) FROM typmod_values ORDER BY id"]
  in
  strings (List.map rounded ~f:(Option.map ~f:Float.to_string));
  strings
    (let open! Stdlib in
     [%pgsql conn "SELECT round(n,1) FROM typmod_values ORDER BY id"]);
  integers
    (let open! Stdlib in
     [%pgsql conn "SELECT abs(-id) FROM typmod_values ORDER BY id"]);
  let key = "name" in
  strings
    (let open! Stdlib in
     [%pgsql conn "SELECT ('{\"name\":\"Ada\"}'::jsonb)->>$key"]);
  let path = [ Some "a"; Some "b" ] in
  strings
    (let open! Stdlib in
     [%pgsql conn "SELECT ('{\"a\":{\"b\":7}}'::json)#>>$path"]);
  let rows : bool option list =
    let open! Stdlib in
    [%pgsql conn "SELECT note IS DISTINCT FROM NULL FROM join_people ORDER BY id"]
  in
  assert (List.equal (Option.equal Bool.equal) rows [ Some false; Some true; Some false ])
;;

let lateral conn =
  let maximum = 1L in
  let rows : (int32 * string option) list =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT p.id,q.label FROM join_people p LEFT JOIN LATERAL (SELECT l.label FROM join_links l WHERE l.person_id=p.id ORDER BY l.id LIMIT $maximum) q ON true ORDER BY p.id"]
  in
  assert (
    List.equal
      (fun (a, b) (c, d) -> Int32.equal a c && Option.equal String.equal b d)
      rows
      [ 1l, Some "first"; 2l, Some "second"; 3l, None ]);
  List.iter rows ~f:(fun (id, label) ->
    Stdlib.Printf.printf "%ld:%s\n" id (Option.value label ~default:"NULL"));
  let rows : int32 list =
    let open! Stdlib in
    [%pgsql conn "SELECT q.id FROM join_people p, LATERAL (SELECT p.id) q ORDER BY q.id"]
  in
  assert (List.equal Int32.equal rows [ 1l; 2l; 3l ])
;;

let windows conn =
  let duration = PGOCaml.interval_of_string "1 day" in
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT count(*) OVER(ORDER BY t RANGE $duration PRECEDING) FROM typmod_values ORDER BY id"]);
  let distance = 1.5 in
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT count(*) OVER(ORDER BY id::real RANGE $distance PRECEDING) FROM join_people ORDER BY id"]);
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT count(*) OVER(PARTITION BY active ORDER BY id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING EXCLUDE NO OTHERS) FROM join_links ORDER BY id"]);
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT count(*) OVER(ORDER BY id GROUPS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW EXCLUDE GROUP) FROM join_people ORDER BY id"]);
  bigints
    (let open! Stdlib in
     [%pgsql conn "SELECT row_number() OVER(ORDER BY id) FROM join_people ORDER BY id"]);
  let rows
    : (int64 option * int64 option * float option * float option * int32 option) list
    =
    let open! Stdlib in
    [%pgsql
      conn
        "SELECT rank() OVER w,dense_rank() OVER w,percent_rank() OVER w,cume_dist() OVER w,ntile(2) OVER w FROM join_people WINDOW w AS(ORDER BY id) ORDER BY id"]
  in
  List.iter rows ~f:(fun (rank, dense, percent, cume, tile) ->
    assert (Option.equal Int64.equal rank dense);
    Stdlib.Printf.printf
      "%s:%s:%s:%s\n"
      (Option.value_map rank ~default:"NULL" ~f:Int64.to_string)
      (Option.value_map percent ~default:"NULL" ~f:Float.to_string)
      (Option.value_map cume ~default:"NULL" ~f:Float.to_string)
      (Option.value_map tile ~default:"NULL" ~f:Int32.to_string));
  let distance = 1l
  and fallback = 0l in
  integers
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT lag(id,$distance,$fallback) OVER(ORDER BY id) FROM join_people ORDER BY id"]);
  strings
    (let open! Stdlib in
     [%pgsql conn "SELECT lead(name) OVER(ORDER BY id) FROM join_people ORDER BY id"]);
  strings
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT first_value(name) OVER w FROM join_people WINDOW w AS(ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) ORDER BY id"]);
  strings
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT last_value(name) OVER(ORDER BY id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) FROM join_people ORDER BY id"]);
  strings
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT nth_value(name,2) OVER(ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) FROM join_people ORDER BY id"]);
  let preceding = 1L in
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT sum(id) OVER(ORDER BY id ROWS BETWEEN $preceding PRECEDING AND CURRENT ROW EXCLUDE CURRENT ROW) FROM join_people ORDER BY id"]);
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT count(*) OVER(ORDER BY id GROUPS 1 PRECEDING EXCLUDE TIES) FROM join_people ORDER BY id"]);
  let range = 1l in
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT count(*) OVER(ORDER BY id RANGE $range PRECEDING) FROM join_people ORDER BY id"]);
  strings
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT sum(count(*)) OVER(ORDER BY name) FROM join_people GROUP BY name ORDER BY name"]);
  bigints
    (let open! Stdlib in
     [%pgsql
       conn
         "SELECT count(*) FILTER(WHERE active) OVER(base ORDER BY id) FROM join_links WINDOW base AS() ORDER BY id"])
;;

let dml conn =
  exec conn "BEGIN";
  Exn.protect
    ~finally:(fun () -> exec conn "ROLLBACK")
    ~f:(fun () ->
      let rows =
        let open! Stdlib in
        [%pgsql.object
          conn
            "UPDATE join_people p SET name=l.label FROM join_links l WHERE p.id=l.person_id RETURNING p.id AS identifier,p.name,l.label"]
      in
      let rows =
        List.sort rows ~compare:(fun a b -> Int32.compare a#identifier b#identifier)
      in
      List.iter rows ~f:(fun row ->
        assert (Option.equal String.equal row#label (Some row#name));
        Stdlib.Printf.printf "%ld:%s\n" row#identifier row#name);
      let deleted : int32 list =
        let open! Stdlib in
        [%pgsql
          conn
            "DELETE FROM join_people p USING join_links l WHERE p.id=l.person_id RETURNING p.id"]
      in
      assert (List.equal Int32.equal (List.sort deleted ~compare:Int32.compare) [ 1l; 2l ]));
  let ids : int32 list =
    let open! Stdlib in
    [%pgsql conn "SELECT id FROM join_people ORDER BY id"]
  in
  assert (List.equal Int32.equal ids [ 1l; 2l; 3l ]);
  exec conn "BEGIN";
  Exn.protect
    ~finally:(fun () -> exec conn "ROLLBACK")
    ~f:(fun () ->
      (let open! Stdlib in
       [%pgsql
         conn
           "WITH names AS(SELECT person_id,label FROM join_links) UPDATE join_people p SET name=names.label FROM names WHERE p.id=names.person_id"]);
      let open! Stdlib in
      [%pgsql
        conn
          "WITH ids AS(SELECT person_id FROM join_links) DELETE FROM join_people p USING ids WHERE p.id=ids.person_id"])
;;

let main conn =
  exec
    conn
    "CREATE TABLE IF NOT EXISTS join_people(id integer NOT NULL,name text NOT NULL,note text)";
  exec
    conn
    "CREATE TABLE IF NOT EXISTS join_links(id integer NOT NULL,person_id integer NOT NULL,label text,active boolean NOT NULL)";
  exec conn "TRUNCATE join_people,join_links";
  exec
    conn
    "INSERT INTO join_people VALUES(1,'Ada',NULL),(2,'Grace','note'),(3,'Lin',NULL)";
  exec conn "INSERT INTO join_links VALUES(1,1,'first',true),(2,2,'second',false)";
  exec conn "DROP TABLE IF EXISTS typmod_values";
  exec
    conn
    "CREATE TABLE typmod_values(id integer PRIMARY KEY,v varchar(10) NOT NULL,c char(3) NOT NULL,n numeric(8,2) NOT NULL,t timestamp(3) NOT NULL,z timestamptz(3) NOT NULL,tm time(3) NOT NULL,i interval day to second(3) NOT NULL,vs varchar(10)[] NOT NULL)";
  exec
    conn
    "INSERT INTO typmod_values VALUES(1,'Ada','abc',12.34,'2026-10-15 12:34:56.123','2026-10-15 12:34:56.123+00','12:34:56.123','2 days 12:34:56.123',ARRAY['x',NULL]),(2,'Grace','def',56.78,'2026-10-16 12:34:56.123','2026-10-16 12:34:56.123+00','12:34:56.123','3 days 12:34:56.123',ARRAY['y'])";
  casts conn;
  functions conn;
  lateral conn;
  windows conn;
  dml conn
;;

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect ~finally:(fun () -> PGOCaml.close conn) ~f:(fun () -> main conn)
;;
