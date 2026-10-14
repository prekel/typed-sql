open! Base
module Real_pgocaml = PGOCaml

module PGOCaml = struct
  include (Real_pgocaml : module type of Real_pgocaml with type 'a t := 'a Real_pgocaml.t)

  type 'a t =
    { mutable data : 'a option
    ; mutable prepared : (string * string) list
    ; mutable parameters : string option list
    ; rows : string option list list
    }

  let create rows = { data = None; prepared = []; parameters = []; rows }
  let bind value f = f value
  let return value = value

  let private_data conn =
    match conn.data with
    | Some data -> data
    | None -> Stdlib.raise Stdlib.Not_found
  ;;

  let set_private_data conn data = conn.data <- Some data
  let prepare conn ~name ~query () = conn.prepared <- (name, query) :: conn.prepared

  let execute_rev conn ~name:_ ~params () =
    conn.parameters <- params;
    List.rev conn.rows
  ;;
end

let%test_unit "ordinary quotation preserves integer types and tuple order" =
  let conn = PGOCaml.create [ [ Some "7"; Some "42"; Some "9000000000" ] ] in
  let result : (int * int32 * int64) list =
    [%pgsql conn "SELECT small_value, id, big_value FROM people"]
  in
  assert (
    List.equal
      (fun (a, b, c) (x, y, z) -> Int.equal a x && Int32.equal b y && Int64.equal c z)
      result
      [ 7, 42l, 9000000000L ])
;;

let%test_unit "anonymous quoted SQL binds values and preserves row order" =
  let conn = PGOCaml.create [ [ Some "Ada" ]; [ Some "Grace" ] ] in
  let id = 42l in
  let result : string list =
    [%pgsql
      conn
        {|SELECT name FROM people
WHERE (id = $id AND id = ${Int32.succ id}) ORDER BY id DESC|}]
  in
  assert (List.equal String.equal result [ "Ada"; "Grace" ]);
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some "42"; Some "43" ]);
  assert (
    String.equal
      (snd (List.hd_exn conn.prepared))
      "SELECT name FROM people\nWHERE (id = $1 AND id = $2) ORDER BY id DESC")
;;

let%test_unit "named quoted SQL returns objects with aliases" =
  let conn = PGOCaml.create [ [ Some "42"; Some "Ada" ] ] in
  let result =
    [%pgsql.object
      conn {sql|SELECT p.id AS identifier, p.name FROM public.people AS p|sql}]
  in
  let row = List.hd_exn result in
  assert (Int32.equal row#identifier 42l);
  assert (String.equal row#name "Ada")
;;

let%test_unit "objects also accept ordinary and anonymous quoted SQL" =
  let conn = PGOCaml.create [ [ Some "Ada" ] ] in
  let ordinary = List.hd_exn [%pgsql.object conn "SELECT name FROM people"] in
  let quoted = List.hd_exn [%pgsql.object conn {|SELECT name FROM people|}] in
  assert (String.equal ordinary#name quoted#name)
;;

let%test_unit "named quoted tuple SQL accepts optional expression parameters" =
  let conn = PGOCaml.create [ [ None ] ] in
  let note = None in
  let result : string option list =
    [%pgsql conn {sql|SELECT note FROM people WHERE note = $?{note}|sql}]
  in
  assert (List.equal (Option.equal String.equal) result [ None ]);
  assert (List.equal (Option.equal String.equal) conn.parameters [ None ])
;;

let%test_unit "optional named parameters remain SQL NULL" =
  let conn = PGOCaml.create [] in
  let id = None in
  let result = [%pgsql conn "SELECT id FROM people WHERE id = $?id"] in
  assert (List.is_empty result);
  assert (List.equal (Option.equal String.equal) conn.parameters [ None ])
;;

let%test_unit "nullable-results makes every field optional" =
  let conn = PGOCaml.create [ [ None; None ] ] in
  let result : (int32 option * string option) list =
    [%pgsql conn "nullable-results" "SELECT id, note FROM people"]
  in
  match result with
  | [ (None, None) ] -> ()
  | _ -> failwith "expected optional NULL fields"
;;

let%test_unit "NULL in a required column preserves upstream failure" =
  let conn = PGOCaml.create [ [ None ] ] in
  match Result.try_with (fun () -> [%pgsql conn "SELECT id FROM people"]) with
  | Error (Stdlib.Failure message) ->
    assert (String.is_substring message ~substring:"nullable-results")
  | _ -> failwith "expected nullability failure"
;;

let%test_unit "row width mismatch raises PGOCaml.Error" =
  let conn = PGOCaml.create [ [] ] in
  match Result.try_with (fun () -> [%pgsql conn "SELECT id FROM people"]) with
  | Error (PGOCaml.Error _) -> ()
  | _ -> failwith "expected row width error"
;;

let%test_unit "prepared handles are reused for changing values" =
  let conn = PGOCaml.create [] in
  let select id = [%pgsql conn "SELECT name FROM people WHERE id = $id"] in
  ignore (select 1l : string list);
  ignore (select 2l : string list);
  assert (Int.equal (List.length conn.prepared) 1);
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some "2" ])
;;

let%test_unit "embedded OCaml expressions preserve nested strings and records" =
  let conn = PGOCaml.create [] in
  ignore
    ([%pgsql conn {sql|SELECT id FROM people WHERE name = ${("}" ^ {|{nested}|})}|sql}]
     : int32 list);
  assert (List.equal (Option.equal String.equal) conn.parameters [ Some "}{nested}" ])
;;

let%test_unit "quoted SQL identifiers preserve case and escaped quotes" =
  let conn = PGOCaml.create [ [ Some "value" ] ] in
  let result = [%pgsql conn {|SELECT "odd""name" FROM quoted|}] in
  assert (List.equal String.equal result [ "value" ])
;;
