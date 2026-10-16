open! Base
open Typed_sql
module Q = Cached_queries.Queries

module type S = sig
  val run : ('i, 'o, [ `Postgresql ]) Statement.t -> 'i -> 'o Lwt.t
end

let ( let* ) = Lwt.bind

type person =
  { id : int
  ; name : string
  }

let person_of_object (person : < id : int ; name : string >) =
  { id = person#id; name = person#name }
;;

let scenario (module R : S) =
  let* inserted = R.run Q.insert_direct { Q.id = 44; name = "Runtime" } in
  assert (
    List.equal
      (fun (a, b) (c, d) -> Int.equal a c && String.equal b d)
      inserted
      [ 44, "Runtime" ]);
  let expected_json =
    [ Some `Null
    ; None
    ; Some (`Assoc [ "a", `Int 1 ])
    ; Some (`String "text")
    ; Some (`List [ `Int 1 ])
    ; Some (`Bool true)
    ; Some (`Int 42)
    ]
  in
  let check_json = function
    | [ rows ] -> assert (List.equal (Option.equal Yojson.Safe.equal) rows expected_json)
    | _ -> failwith "expected one multiset row"
  in
  let* nested_json = R.run Q.nested_json () in
  check_json nested_json;
  let* aggregated_json = R.run Q.aggregated_json () in
  check_json aggregated_json;
  let* json_text = R.run Q.nested_json_text () in
  check_json json_text;
  let* locked = R.run Q.nested_locked () in
  assert (List.equal (List.equal Int.equal) locked [ [ 44 ] ]);
  let* locked_cte = R.run Q.nested_locked_cte () in
  assert (List.equal (List.equal Int.equal) locked_cte [ [ 44 ] ]);
  let* people = R.run Q.find_direct 44 in
  assert (List.equal String.equal (List.map people ~f:(fun p -> p#name)) [ "Runtime" ]);
  let* nullable = R.run Q.nullable_people_direct 44 in
  assert (
    List.equal
      (Option.equal String.equal)
      (List.map nullable ~f:(fun p -> p#name))
      [ Some "Runtime" ]);
  let* absent = R.run Q.nullable_direct None in
  assert (List.equal (Option.equal String.equal) absent [ None ]);
  let* present = R.run Q.nullable_direct (Some "value") in
  assert (List.equal (Option.equal String.equal) present [ Some "value" ]);
  let* constant = R.run Q.constant_statement () in
  assert (List.equal (Option.equal Int.equal) constant [ Some 1 ]);
  let* _ = R.run Q.delete_direct 44 in
  let* deleted = R.run Q.find_direct 44 in
  assert (List.is_empty deleted);
  let* _ = R.run Q.dsl_insert (43, "DSL") in
  let* people = R.run Q.find 43 in
  (match List.map people ~f:person_of_object with
   | [ person ] -> assert (Int.equal person.id 43 && String.equal person.name "DSL")
   | _ -> failwith "expected the DSL row through an object converter");
  let* _ = R.run Q.delete 43 in
  let* initial = R.run Q.insert (42, "Ada") in
  assert (
    List.equal
      (fun (a, b) (c, d) -> Int.equal a c && String.equal b d)
      initial
      [ 42, "Ada" ]);
  let* _ = R.run Q.update (42, "Grace") in
  let* people = R.run Q.find 42 in
  assert (List.equal String.equal (List.map people ~f:(fun p -> p#name)) [ "Grace" ]);
  let* nullable_people = R.run Q.nullable_people 42 in
  assert (
    List.equal
      (Option.equal String.equal)
      (List.map nullable_people ~f:(fun p -> p#name))
      [ Some "Grace" ]);
  let* optional = R.run Q.nullable (Some "optional") in
  assert (List.equal (Option.equal String.equal) optional [ Some "optional" ]);
  let* absent = R.run Q.nullable None in
  assert (List.equal (Option.equal String.equal) absent [ None ]);
  let* union = R.run Q.union () in
  assert (List.equal (Option.equal Int.equal) union [ Some 1; Some 42 ]);
  let* nested = R.run Q.nested () in
  assert (List.equal (List.equal (Option.equal Int.equal)) nested [ [ Some 1 ] ]);
  let* derived = R.run Q.derived () in
  assert (List.equal (Option.equal Int.equal) derived [ Some 1 ]);
  let* cte = R.run Q.cte () in
  assert (List.equal (Option.equal Int.equal) cte [ Some 1 ]);
  let array =
    Pg_array.of_string ~decode:(fun value -> Ok (Int.of_string value)) "[0:2]={1,NULL,3}"
    |> Result.ok_or_failwith
  in
  let* arrays = R.run Q.array_input array in
  (match arrays with
   | [ Some decoded ] ->
     assert (
       List.equal
         (Option.equal Int.equal)
         (Pg_array.elements decoded)
         (Pg_array.elements array));
     assert (List.equal Int.equal (Pg_array.lower_bounds decoded) [ 0 ])
   | _ -> failwith "expected a round-trip PostgreSQL array");
  let* moods = R.run Q.enum_input "ready" in
  assert (List.equal (Option.equal String.equal) moods [ Some "ready" ]);
  let* tags = R.run Q.domain_input 3 in
  assert (List.equal (Option.equal Int.equal) tags [ Some 3 ]);
  let* types = R.run Q.types () in
  (match types with
   | [ (Some amount, Some numbers, Some mood) ] ->
     assert (String.equal (Decimal.to_string amount) "1.25");
     assert (String.equal mood "ready");
     assert (
       List.equal
         (Option.equal Int.equal)
         (Pg_array.elements numbers)
         [ Some 1; None; Some 3 ])
   | _ -> failwith "unexpected typed output");
  let* inserted = R.run Q.modifying_cte () in
  assert (List.equal Int.equal inserted [ 7 ]);
  let* _ = R.run Q.delete 7 in
  let* _ = R.run Q.delete 42 in
  let* empty = R.run Q.find 42 in
  assert (List.is_empty empty);
  Lwt.return ()
;;

let caqti () =
  let module A = Typed_sql_caqti_lwt in
  let* connection = Caqti_lwt_unix.connect (Uri.of_string "postgresql://") in
  let conn =
    match connection with
    | Ok conn -> conn
    | Error error -> failwith (Caqti.Error.show error)
  in
  let module Conn = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize
    (fun () ->
       let* result =
         A.transaction ~conn ~f:(fun conn ->
           let module R = struct
             let run statement input =
               let* result = A.run ~conn statement input in
               match result with
               | Ok value -> Lwt.return value
               | Error error -> Lwt.fail_with (A.error_to_string error)
             ;;
           end
           in
           let* () = scenario (module R) in
           Lwt.return (Ok ()))
       in
       match result with
       | Ok () -> Lwt.return ()
       | Error error -> Lwt.fail_with (A.error_to_string error))
    Conn.disconnect
;;

let pgocaml () =
  let module A = Typed_sql_pgocaml_lwt in
  let host, unix_domain_socket_dir =
    match Stdlib.Sys.getenv_opt "PGHOST" with
    | Some host when String.is_prefix host ~prefix:"/" -> None, Some host
    | host -> host, None
  in
  let* conn = A.Pgocaml.connect ?host ?unix_domain_socket_dir () in
  Lwt.finalize
    (fun () ->
       let* result =
         A.transaction ~conn ~f:(fun conn ->
           let module R = struct
             let run statement input =
               let* result = A.run ~conn statement input in
               match result with
               | Ok value -> Lwt.return value
               | Error error -> Lwt.fail_with (A.error_to_string error)
             ;;
           end
           in
           let* () = scenario (module R) in
           Lwt.return (Ok ()))
       in
       match result with
       | Ok () -> Lwt.return ()
       | Error error -> Lwt.fail_with (A.error_to_string error))
    (fun () -> A.Pgocaml.close conn)
;;

let () =
  Lwt_main.run
    (let* () = caqti () in
     pgocaml ())
;;
