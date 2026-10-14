open! Base
module PGOCaml = Quotation_test.PGOCaml

let%test_unit "INSERT without RETURNING has type unit and binds all rows" =
  let conn = PGOCaml.create [] in
  let first = 1l in
  let second = 2l in
  let note = None in
  let result : unit =
    [%pgsql
      conn
        {|INSERT INTO ppx_items (id, note) VALUES ($first, $?note), ($second, DEFAULT)|}]
  in
  ignore (result : unit);
  assert (
    List.equal (Option.equal String.equal) conn.parameters [ Some "1"; None; Some "2" ]);
  assert (
    String.equal
      (snd (List.hd_exn conn.prepared))
      "INSERT INTO ppx_items (id, note) VALUES ($1, $2), ($3, DEFAULT)")
;;

let%test_unit "DEFAULT VALUES needs no parameters" =
  let conn = PGOCaml.create [] in
  let result : unit = [%pgsql conn "INSERT INTO ppx_items DEFAULT VALUES"] in
  ignore (result : unit);
  assert (List.is_empty conn.parameters)
;;

let%test_unit "UPDATE binds SET before WHERE and returns nullable tuples" =
  let conn = PGOCaml.create [ [ Some "42"; None ]; [ Some "43"; Some "note" ] ] in
  let note = None in
  let id = 42l in
  let rows : (int32 * string option) list =
    [%pgsql
      conn
        {sql|UPDATE ppx_items AS i SET note = $?{note}, name = ${"Ada"} WHERE (i.id = $id) RETURNING i.id, i.note|sql}]
  in
  assert (
    List.equal (Option.equal String.equal) conn.parameters [ None; Some "Ada"; Some "42" ]);
  assert (
    List.equal
      (fun (left_id, left_note) (right_id, right_note) ->
         Int32.equal left_id right_id && Option.equal String.equal left_note right_note)
      rows
      [ 42l, None; 43l, Some "note" ])
;;

let%test_unit "DELETE without WHERE is a command" =
  let conn = PGOCaml.create [] in
  let result : unit = [%pgsql conn "DELETE FROM ppx_items"] in
  ignore (result : unit);
  assert (String.equal (snd (List.hd_exn conn.prepared)) "DELETE FROM ppx_items")
;;

let%test_unit "DELETE RETURNING yields a scalar list" =
  let conn = PGOCaml.create [ [ Some "Ada" ] ] in
  let id = 42l in
  let rows : string list =
    [%pgsql conn "DELETE FROM ppx_items WHERE id = $id RETURNING name"]
  in
  assert (List.equal String.equal rows [ "Ada" ])
;;

let%test_unit "INSERT RETURNING objects honor aliases" =
  let conn = PGOCaml.create [ [ Some "42"; Some "Ada" ] ] in
  let id = 42l in
  let name = "Ada" in
  let row =
    List.hd_exn
      [%pgsql.object
        conn
          "INSERT INTO ppx_items AS i (id, name) VALUES ($id, $name) RETURNING i.id AS identifier, i.name"]
  in
  assert (Int32.equal row#identifier 42l && String.equal row#name "Ada")
;;

let%test_unit "RETURNING wildcard uses the same scalar codecs and nullability" =
  let conn =
    PGOCaml.create [ [ Some "1"; Some "42"; Some "Ada"; None; Some "{}"; Some "0" ] ]
  in
  let rows : (int32 * int32 * string * string option * string * int32) list =
    [%pgsql conn "DELETE FROM ppx_items AS i RETURNING i.*"]
  in
  match rows with
  | [ (tenant, id, name, None, document, revision) ] ->
    assert (Int32.equal tenant 1l && Int32.equal id 42l && Int32.equal revision 0l);
    assert (String.equal name "Ada" && String.equal document "{}")
  | _ -> failwith "expected wildcard RETURNING row"
;;

let%test_unit "nullable-results also applies to DML RETURNING" =
  let conn = PGOCaml.create [ [ None ] ] in
  let rows : int32 option list =
    [%pgsql
      conn "nullable-results" "UPDATE ppx_items SET revision = DEFAULT RETURNING id"]
  in
  assert (List.equal (Option.equal Int32.equal) rows [ None ])
;;

let%test_unit "DO NOTHING with no returned rows is an empty list" =
  let conn = PGOCaml.create [] in
  let id = 42l in
  let rows : int32 list =
    [%pgsql
      conn "INSERT INTO ppx_items (id) VALUES ($id) ON CONFLICT DO NOTHING RETURNING id"]
  in
  assert (List.is_empty rows)
;;

let%test_unit "upsert preserves parameter order across all clauses" =
  let conn = PGOCaml.create [ [ Some "42" ] ] in
  let id = 42l in
  let tenant = 1l in
  let name = "Ada" in
  let replacement = Some "Grace" in
  let rows : int32 list =
    [%pgsql
      conn
        "INSERT INTO ppx_items AS i (tenant, id, name) VALUES ($tenant, $id, $name) ON CONFLICT (id, tenant) DO UPDATE SET name = $?replacement, note = EXCLUDED.note, revision = DEFAULT WHERE i.id = $id AND excluded.tenant = ${tenant} RETURNING i.id"]
  in
  assert (List.equal Int32.equal rows [ 42l ]);
  assert (
    List.equal
      (Option.equal String.equal)
      conn.parameters
      [ Some "1"; Some "42"; Some "Ada"; Some "Grace"; Some "42"; Some "1" ])
;;

let%test_unit "DML prepared statements are reused for changing values" =
  let conn = PGOCaml.create [] in
  let update name = [%pgsql conn "UPDATE ppx_items SET name = $name"] in
  update "Ada";
  update "Grace";
  assert (Int.equal (List.length conn.prepared) 1);
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some "Grace" ])
;;

let%test_unit "JSON values serialize for writes" =
  let conn = PGOCaml.create [] in
  let document = "{\"id\":1}" in
  [%pgsql conn "UPDATE ppx_items SET document = $document"];
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some document ])
;;

let%test_unit "DML preserves driver exceptions" =
  let module PGOCaml = struct
    include PGOCaml

    let execute_rev _ ~name:_ ~params:_ () = Stdlib.raise (Error "write failed")
  end
  in
  let conn = PGOCaml.create [] in
  match Result.try_with (fun () -> [%pgsql conn "DELETE FROM ppx_items"]) with
  | Error (PGOCaml.Error message) -> assert (String.equal message "write failed")
  | _ -> failwith "expected the original PGOCaml exception"
;;

let%test_unit "RETURNING preserves required NULL failure" =
  let conn = PGOCaml.create [ [ None ] ] in
  match
    Result.try_with (fun () -> [%pgsql conn "DELETE FROM ppx_items RETURNING id"])
  with
  | Error (Stdlib.Failure message) ->
    assert (String.is_substring message ~substring:"nullable-results")
  | _ -> failwith "expected nullability failure"
;;

let%test_unit "RETURNING preserves row width errors" =
  let conn = PGOCaml.create [ [] ] in
  match
    Result.try_with (fun () -> [%pgsql conn "DELETE FROM ppx_items RETURNING id"])
  with
  | Error (PGOCaml.Error _) -> ()
  | _ -> failwith "expected row width error"
;;
