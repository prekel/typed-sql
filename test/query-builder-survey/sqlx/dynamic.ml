open! Base
open Typed_sql

(* $MDX part-begin=helpers *)
module Raw = Raw_sql.Postgresql

type sort =
  | Name_asc
  | Name_desc

type condition =
  | Min_id of int
  | Name_like of string

type field =
  | Name of string
  | Age of int option

let text = Raw.unsafe_sql
let int value = Raw.bind Db_type.int (Expr.constant Db_type.int value)
let string value = Raw.bind Db_type.text (Expr.constant Db_type.text value)
let id_output = Raw_sql.Output.field ~name:(Identifier.of_string_exn "id") Db_type.int

let user_output =
  let%map.Raw_sql.Output id = id_output
  and name = Raw_sql.Output.field ~name:(Identifier.of_string_exn "name") Db_type.text in
  id, name
;;

let separated ~sep lists = List.concat (List.intersperse lists ~sep:[ text sep ])
let select parts = Raw.select ~output:user_output parts
let select_ids parts = Raw.select ~output:id_output parts
let rows_required = Error "rows must not be empty"

(* $MDX part-end *)

(* $MDX part-begin=sx31 *)
let sx31 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun name ->
    select
      ([ text "SELECT id, name FROM users" ]
       @ (match name with
          | None -> []
          | Some name -> [ text " WHERE name = "; string name ])
       @ [ text " ORDER BY id" ]))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx32 *)
let sx32 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun conditions ->
    let predicates =
      List.map conditions ~f:(function
        | Min_id value -> [ text "id > "; int value ]
        | Name_like value -> [ text "name LIKE "; string value ])
    in
    select
      ([ text "SELECT id, name FROM users" ]
       @ (match predicates with
          | [] -> []
          | _ -> [ text " WHERE (" ] @ separated ~sep:" OR " predicates @ [ text ")" ])
       @ [ text " ORDER BY id" ]))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx33 *)
let sx33 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun ids ->
    let predicate =
      match ids with
      | [] -> [ text "FALSE" ]
      | _ ->
        [ text "id IN (" ]
        @ separated ~sep:", " (List.map ids ~f:(fun id -> [ int id ]))
        @ [ text ")" ]
    in
    select
      ([ text "SELECT id, name FROM users WHERE " ] @ predicate @ [ text " ORDER BY id" ]))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx34 *)
let sx34 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun keys ->
    let predicate =
      match keys with
      | [] -> [ text "FALSE" ]
      | _ ->
        [ text "(id, name) IN (" ]
        @ separated
            ~sep:", "
            (List.map keys ~f:(fun (id, name) ->
               [ text "("; int id; text ", "; string name; text ")" ]))
        @ [ text ")" ]
    in
    select
      ([ text "SELECT id, name FROM users WHERE " ] @ predicate @ [ text " ORDER BY id" ]))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx35 *)
let sx35 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun sort ->
    select
      [ text "SELECT id, name FROM users ORDER BY "
      ; text
          (match sort with
           | Name_asc -> "name ASC, id"
           | Name_desc -> "name DESC, id")
      ])
;;

(* $MDX part-end *)

(* $MDX part-begin=sx36 *)
let sx36 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun with_posts ->
    select
      ([ text "SELECT DISTINCT u.id, u.name FROM users u" ]
       @ (if with_posts then
            [ text " JOIN posts p ON p.user_id = u.id" ]
          else
            [])
       @ [ text " ORDER BY u.id" ]))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx37 *)
let sx37 =
  Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun names ->
    let branches =
      List.map names ~f:(fun name ->
        [ text "SELECT id FROM users WHERE name = "; string name ])
    in
    select_ids
      (match branches with
       | [] -> [ text "SELECT id FROM users WHERE FALSE ORDER BY id" ]
       | _ -> separated ~sep:" UNION ALL " branches @ [ text " ORDER BY id" ]))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx38 *)
let sx38 rows =
  match rows with
  | [] -> rows_required
  | _ ->
    Ok
      (Statement.Dynamic.command ~dialect:Dialect.postgresql (fun () ->
         Raw.command
           ([ text "INSERT INTO users (id, name) VALUES " ]
            @ separated
                ~sep:", "
                (List.map rows ~f:(fun (id, name) ->
                   [ text "("; int id; text ", "; string name; text ")" ])))))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx39 *)
let sx39 ~id ~name ~age =
  let fields =
    Option.to_list (Option.map name ~f:(fun value -> Name value))
    @ Option.to_list (Option.map age ~f:(fun value -> Age value))
  in
  match fields with
  | [] -> Error "at least one SET field is required"
  | _ ->
    Ok
      (Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
         let assignments =
           List.map fields ~f:(function
             | Name value -> [ text "name = "; string value ]
             | Age value ->
               [ text "age = "
               ; Raw.bind
                   (Db_type.option Db_type.int)
                   (Expr.constant (Db_type.option Db_type.int) value)
               ])
         in
         Raw.returning
           ~output:user_output
           ([ text "UPDATE users SET " ]
            @ separated ~sep:", " assignments
            @ [ text " WHERE id = "; int id; text " RETURNING id, name" ])))
;;

(* $MDX part-end *)

(* $MDX part-begin=sx40 *)
let sx40 rows =
  match rows with
  | [] -> rows_required
  | _ ->
    Ok
      (Statement.Dynamic.query_many ~dialect:Dialect.postgresql (fun () ->
         Raw.returning
           ~output:user_output
           ([ text "UPDATE users u SET name = v.name FROM (VALUES " ]
            @ separated
                ~sep:", "
                (List.map rows ~f:(fun (id, name) ->
                   [ text "("; int id; text "::int4, "; string name; text "::text)" ]))
            @ [ text ") AS v(id, name) WHERE u.id = v.id RETURNING u.id, u.name" ])))
;;
(* $MDX part-end *)
