open! Base

let predicates conn (low : int32) (high : int32) (pattern : string) : int32 list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql
    conn
      "SELECT id FROM native_items WHERE NOT (id < $low) AND id BETWEEN $low AND $high AND required_value ILIKE $pattern ORDER BY id"]
;;

let pagination conn (limit : int64 option) (offset : int64) : int32 list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql conn "SELECT id FROM native_items ORDER BY id LIMIT $?limit OFFSET $offset"]
;;

let fixed_in conn (id : int32) : int32 list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql conn "SELECT id FROM native_items WHERE id IN ($id, 41, 43)"]
;;

let widened_in conn (value : int32) : int32 list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql conn "SELECT id FROM native_items WHERE small_value IN ($value, 7)"]
;;

(* Upstream 4.4.0 can select named enum converters from its default config.
   Keep this comparison on built-in output codecs; enum conversion is tested
   separately against PostgreSQL without enabling custom conversion config. *)
let enum_predicate conn : int32 list =
  let open Stdlib in
  [%pgsql conn "SELECT id FROM native_items WHERE mood IN ('happy', 'sad')"]
;;

let domain conn (small : int) : int list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql conn "SELECT small_value FROM native_items WHERE small_value = $small"]
;;

let domain_nullable conn : string option list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql conn "SELECT required_value FROM native_items"]
;;

let arrays conn (numbers : int32 option list) : int32 option list list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql conn "SELECT numbers FROM native_items WHERE numbers = $numbers"]
;;

let any conn (ids : int32 option list) : int32 list =
  (* Upstream generates unqualified Stdlib calls. *)
  let open Stdlib in
  [%pgsql conn "SELECT id FROM native_items WHERE id = ANY($ids)"]
;;

let () =
  let conn = PGOCaml.connect () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      let print_ids values =
        Stdlib.print_endline (String.concat ~sep:"," (List.map values ~f:Int32.to_string))
      in
      print_ids (predicates conn 40l 43l "req%");
      print_ids (pagination conn (Some 1L) 0L);
      print_ids (fixed_in conn 42l);
      print_ids (widened_in conn 7l);
      print_ids (enum_predicate conn);
      Stdlib.print_endline
        (String.concat ~sep:"," (List.map (domain conn 7) ~f:Int.to_string));
      Stdlib.print_endline
        (String.concat
           ~sep:","
           (List.map (domain_nullable conn) ~f:(Option.value ~default:"NULL")));
      List.iter (arrays conn []) ~f:(fun values ->
        Stdlib.print_endline (PGOCaml.string_of_int32_array values));
      print_ids (any conn [ Some 42l; None ]))
;;
