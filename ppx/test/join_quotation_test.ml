open! Base
module PGOCaml = Quotation_test.PGOCaml

let%test_unit "joined scalar retains its PGOCaml type" =
  let conn = PGOCaml.create [ [ Some "42" ] ] in
  let rows : int32 list =
    [%pgsql conn "SELECT p.id FROM join_people p JOIN join_links l ON p.id = l.person_id"]
  in
  assert (List.equal Int32.equal rows [ 42l ])
;;

let%test_unit "joined wildcard tuples preserve column order and nullable fields" =
  let conn =
    PGOCaml.create [ [ Some "1"; Some "Ada"; None; Some "10"; Some "1"; None; Some "t" ] ]
  in
  let rows : (int32 * string * string option * int32 * int32 * string option * bool) list =
    [%pgsql
      conn "SELECT * FROM join_people p INNER JOIN join_links l ON p.id = l.person_id"]
  in
  let person, name, note, link, owner, label, active = List.hd_exn rows in
  assert (Int32.equal person 1l);
  assert (String.equal name "Ada");
  assert (Option.is_none note);
  assert (Int32.equal link 10l);
  assert (Int32.equal owner 1l);
  assert (Option.is_none label);
  assert active
;;

let%test_module "joined objects and application converter" =
  (module struct
    type t =
      { identifier : int32
      ; name : string
      ; label : string option
      }

    let t_of_pgocaml row =
      { identifier = row#identifier; name = row#name; label = row#label }
    ;;

    let%test_unit "object output preserves the converter boundary" =
      let conn = PGOCaml.create [ [ Some "1"; Some "Ada"; None ] ] in
      let rows =
        [%pgsql.object
          conn
            "SELECT p.id AS identifier, p.name, l.label FROM join_people p JOIN join_links l ON p.id = l.person_id"]
      in
      let converted = List.map rows ~f:t_of_pgocaml in
      let row = List.hd_exn converted in
      assert (Int32.equal row.identifier 1l);
      assert (String.equal row.name "Ada");
      assert (Option.is_none row.label)
    ;;

    let%test_unit "object qualified wildcard retains column names" =
      let conn = PGOCaml.create [ [ Some "1"; Some "Ada"; None ] ] in
      let rows =
        [%pgsql.object
          conn "SELECT p.* FROM join_people p JOIN join_links l ON p.id = l.person_id"]
      in
      let row = List.hd_exn rows in
      assert (Int32.equal row#id 1l);
      assert (String.equal row#name "Ada");
      assert (Option.is_none (row#note : string option))
    ;;
  end)
;;

let%test_unit "nullable-results applies to all joined output fields" =
  let conn = PGOCaml.create [ [ Some "1"; None ] ] in
  let rows : (int32 option * string option) list =
    [%pgsql
      conn
        "nullable-results"
        "SELECT p.id, l.label FROM join_people p JOIN join_links l ON p.id = l.person_id"]
  in
  let id, label = List.hd_exn rows in
  assert (Option.equal Int32.equal id (Some 1l));
  assert (Option.is_none label)
;;

let%test_unit "join parameter values change without changing the prepared SQL" =
  let conn = PGOCaml.create [] in
  let find label name limit =
    [%pgsql
      conn
        "SELECT p.id FROM join_people p JOIN join_links l ON p.id = l.person_id AND l.label = $?label WHERE p.name = $name ORDER BY l.id LIMIT $limit"]
  in
  ignore (find (Some "first") "Ada" 1L : int32 list);
  assert (
    List.equal
      (Option.equal String.equal)
      conn.parameters
      [ Some "first"; Some "Ada"; Some "1" ]);
  ignore (find None "Grace" 2L : int32 list);
  assert (
    List.equal
      (Option.equal String.equal)
      conn.parameters
      [ None; Some "Grace"; Some "2" ]);
  assert (Int.equal (List.length conn.prepared) 1);
  assert (
    String.equal
      (snd (List.hd_exn conn.prepared))
      "SELECT p.id FROM join_people p JOIN join_links l ON p.id = l.person_id AND l.label = $1 WHERE p.name = $2 ORDER BY l.id LIMIT $3")
;;

let%test_unit "quoted aliases resolve without rewriting source SQL" =
  let conn = PGOCaml.create [ [ Some "Ada" ] ] in
  let rows : string list =
    [%pgsql
      conn
        {|SELECT "P".name FROM public.join_people AS "P" JOIN public.join_links AS "L" ON "P".id = "L".person_id|}]
  in
  assert (List.equal String.equal rows [ "Ada" ])
;;
