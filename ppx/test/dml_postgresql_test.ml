open! Base

let exec conn query =
  PGOCaml.prepare conn ~query ();
  ignore (PGOCaml.execute conn ~params:[] () : string option list list)
;;

let reset conn = exec conn "TRUNCATE ppx_items RESTART IDENTITY"

let insert conn ~tenant ~id ~name ~note =
  [%pgsql
    conn
      "INSERT INTO ppx_items (tenant, id, name, note) VALUES ($tenant, $id, $name, $?note)"]
;;

let multirow_insert conn =
  reset conn;
  let first = 10l in
  let second = 20l in
  let first_name = "Ada" in
  let second_name = "Grace" in
  let note = Some "note" in
  let rows : (int32 * string * string option) list =
    [%pgsql
      conn
        {|INSERT INTO ppx_items (id, name, note) VALUES ($first, $first_name, DEFAULT), ($second, $second_name, $?note) RETURNING id, name, note|}]
  in
  let rows =
    List.sort rows ~compare:(fun (left, _, _) (right, _, _) -> Int32.compare left right)
  in
  assert (
    List.equal
      (fun (a, b, c) (x, y, z) ->
         Int32.equal a x && String.equal b y && Option.equal String.equal c z)
      rows
      [ 10l, "Ada", None; 20l, "Grace", Some "note" ])
;;

let default_values conn =
  reset conn;
  let row =
    List.hd_exn [%pgsql.object conn "INSERT INTO ppx_items DEFAULT VALUES RETURNING *"]
  in
  assert (Int32.equal row#tenant 1l && Int32.equal row#id 1l);
  assert (String.equal row#name "unnamed" && Option.is_none row#note);
  assert (String.equal row#document "{}" && Int32.equal row#revision 0l)
;;

let update_with_predicate conn =
  reset conn;
  insert conn ~tenant:1l ~id:10l ~name:"Ada" ~note:(Some "old");
  insert conn ~tenant:1l ~id:20l ~name:"Grace" ~note:None;
  let id = 10l in
  let note = Some "new" in
  let rows : string option list =
    [%pgsql
      conn "UPDATE ppx_items AS i SET note = $?note WHERE (i.id = $id) RETURNING i.note"]
  in
  assert (List.equal (Option.equal String.equal) rows [ Some "new" ]);
  assert (
    List.equal
      (Option.equal String.equal)
      [%pgsql conn "SELECT note FROM ppx_items WHERE id = ${20l}"]
      [ None ])
;;

let update_without_predicate conn =
  reset conn;
  insert conn ~tenant:1l ~id:10l ~name:"Ada" ~note:(Some "old");
  insert conn ~tenant:1l ~id:20l ~name:"Grace" ~note:(Some "old");
  let result : unit = [%pgsql conn "UPDATE ppx_items SET note = DEFAULT"] in
  ignore (result : unit);
  assert (
    List.equal
      (Option.equal String.equal)
      [%pgsql conn "SELECT note FROM ppx_items ORDER BY id"]
      [ None; None ])
;;

let delete_with_predicate conn =
  reset conn;
  insert conn ~tenant:1l ~id:10l ~name:"Ada" ~note:None;
  insert conn ~tenant:1l ~id:20l ~name:"Grace" ~note:None;
  let rows : int32 list =
    [%pgsql conn "DELETE FROM ppx_items AS i WHERE i.id = ${10l} RETURNING i.id"]
  in
  assert (List.equal Int32.equal rows [ 10l ]);
  assert (List.equal Int32.equal [%pgsql conn "SELECT id FROM ppx_items"] [ 20l ])
;;

let delete_without_predicate conn =
  reset conn;
  insert conn ~tenant:1l ~id:10l ~name:"Ada" ~note:None;
  let result : unit = [%pgsql conn "DELETE FROM ppx_items"] in
  ignore (result : unit);
  assert (List.is_empty [%pgsql conn "SELECT id FROM ppx_items"])
;;

let upsert conn =
  reset conn;
  let save ~tenant ~id ~name ~note =
    [%pgsql.object
      conn
        {|INSERT INTO ppx_items AS i (tenant, id, name, note) VALUES ($tenant, $id, $name, $?note)
        ON CONFLICT (id, tenant) DO UPDATE SET name = EXCLUDED.name, note = EXCLUDED.note, revision = DEFAULT
        WHERE (i.id = $id AND EXCLUDED.tenant = $tenant)
        RETURNING i.id AS identifier, i.name, i.note|}]
  in
  let first = List.hd_exn (save ~tenant:1l ~id:10l ~name:"Ada" ~note:None) in
  assert (Int32.equal first#identifier 10l && String.equal first#name "Ada");
  let second =
    List.hd_exn (save ~tenant:1l ~id:10l ~name:"Grace" ~note:(Some "updated"))
  in
  assert (
    String.equal second#name "Grace"
    && Option.equal String.equal second#note (Some "updated"));
  assert (List.equal String.equal [%pgsql conn "SELECT name FROM ppx_items"] [ "Grace" ])
;;

let conflict_do_nothing conn =
  reset conn;
  insert conn ~tenant:1l ~id:10l ~name:"Ada" ~note:None;
  let name = "Ada" in
  let rows : int32 list =
    [%pgsql
      conn
        "INSERT INTO ppx_items (id, name) VALUES (${20l}, $name) ON CONFLICT (name) DO NOTHING RETURNING id"]
  in
  assert (List.is_empty rows);
  let rows : int32 list =
    [%pgsql
      conn
        "INSERT INTO ppx_items (id, name) VALUES (${10l}, ${\"Grace\"}) ON CONFLICT DO NOTHING RETURNING id"]
  in
  assert (List.is_empty rows);
  assert (List.equal Int32.equal [%pgsql conn "SELECT id FROM ppx_items"] [ 10l ])
;;

let conflict_where_false conn =
  reset conn;
  insert conn ~tenant:1l ~id:10l ~name:"Ada" ~note:None;
  let rows : string list =
    [%pgsql
      conn
        "INSERT INTO ppx_items AS i (tenant, id, name) VALUES (${1l}, ${10l}, ${\"Grace\"}) ON CONFLICT (tenant, id) DO UPDATE SET name = EXCLUDED.name WHERE i.id = ${20l} RETURNING i.name"]
  in
  assert (List.is_empty rows);
  assert (List.equal String.equal [%pgsql conn "SELECT name FROM ppx_items"] [ "Ada" ])
;;

let json_write conn =
  reset conn;
  let document = "{\"id\":1}" in
  let result : unit =
    [%pgsql conn "INSERT INTO ppx_items (document) VALUES ($document)"]
  in
  ignore (result : unit);
  assert (
    List.equal String.equal [%pgsql conn "SELECT document FROM ppx_items"] [ document ])
;;

let nullable_returning conn =
  reset conn;
  let rows : int32 option list =
    [%pgsql conn "nullable-results" "INSERT INTO ppx_items DEFAULT VALUES RETURNING id"]
  in
  assert (List.equal (Option.equal Int32.equal) rows [ Some 1l ])
;;

let driver_errors conn =
  reset conn;
  insert conn ~tenant:1l ~id:10l ~name:"Ada" ~note:None;
  assert (
    Result.is_error
      (Result.try_with (fun () -> insert conn ~tenant:1l ~id:10l ~name:"Grace" ~note:None)))
;;

let () =
  let conn = PGOCaml.connect () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      exec
        conn
        "CREATE TABLE public.ppx_items (tenant integer NOT NULL DEFAULT 1, id integer GENERATED BY DEFAULT AS IDENTITY, name text NOT NULL DEFAULT 'unnamed' UNIQUE, note text, document json NOT NULL DEFAULT '{}', revision integer NOT NULL DEFAULT 0, PRIMARY KEY (tenant, id))";
      List.iter
        [ multirow_insert
        ; default_values
        ; update_with_predicate
        ; update_without_predicate
        ; delete_with_predicate
        ; delete_without_predicate
        ; upsert
        ; conflict_do_nothing
        ; conflict_where_false
        ; json_write
        ; nullable_returning
        ; driver_errors
        ]
        ~f:(fun test -> test conn))
;;
