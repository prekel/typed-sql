open! Base
module Type_info = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier
module J = Yojson.Safe.Util

type kind =
  | Select
  | Returning
  | Command
  | Unsupported

type field =
  { name : string
  ; typ : Type_info.postgresql_type_info
  ; nullable : bool
  }

type entry =
  { sql : string
  ; kind : kind
  ; top_level_only : bool
  ; parameters : Type_info.postgresql_type_info list
  ; result : field list option
  }

type t =
  { role : string
  ; search_path : string
  ; entries : entry list
  }

let entries t = t.entries
let find t ~sql = List.find t.entries ~f:(fun entry -> String.equal entry.sql sql)

let kind_to_string = function
  | Select -> "select"
  | Returning -> "returning"
  | Command -> "command"
  | Unsupported -> "unsupported"
;;

let kind ~operation ~rows =
  match operation, rows with
  | Query_kind.Select, true -> Select
  | (Query_kind.Insert | Update | Delete), true -> Returning
  | (Query_kind.Insert | Update | Delete), false -> Command
  | _ -> Unsupported
;;

let create ~role ~search_path entries =
  let entries = List.sort entries ~compare:(fun a b -> String.compare a.sql b.sql) in
  let valid entry =
    let analysis = Query_kind.analyze entry.sql in
    match entry.kind with
    | Unsupported -> true
    | Select | Returning | Command ->
      let expected =
        kind ~operation:analysis.operation ~rows:(Option.is_some entry.result)
      in
      let same_kind =
        match entry.kind, expected with
        | Select, Select | Returning, Returning | Command, Command -> true
        | _ -> false
      in
      same_kind && Bool.equal entry.top_level_only analysis.top_level_only
  in
  match
    List.find_consecutive_duplicate entries ~equal:(fun a b -> String.equal a.sql b.sql)
  with
  | Some _ -> Error "duplicate SQL in query cache"
  | None ->
    if
      List.exists entries ~f:(fun entry ->
        match entry.result with
        | Some [] -> true
        | _ -> false)
    then
      Error "zero-column row results are not supported"
    else if not (List.for_all entries ~f:valid) then
      Error "cached statement kind or placement disagrees with SQL"
    else
      Ok { role; search_path; entries }
;;

let rec encode_type (typ : Type_info.postgresql_type_info) =
  let kind, nested =
    match typ.kind with
    | Native_scalar -> "scalar", []
    | Native_enum labels ->
      "enum", [ "labels", `List (List.map labels ~f:(fun s -> `String s)) ]
    | Native_domain base -> "domain", [ "base", encode_type base ]
    | Native_array element -> "array", [ "element", encode_type element ]
    | Native_opaque -> "opaque", []
  in
  `Assoc
    ([ "schema", `String (I.to_string typ.schema)
     ; "name", `String (I.to_string typ.name)
     ; "kind", `String kind
     ]
     @ nested)
;;

let encode_typed typ = `Assoc [ "type", encode_type typ ]

let to_string t =
  let encode_entry entry =
    let result =
      match entry.result with
      | None -> `Null
      | Some fields ->
        `List
          (List.map fields ~f:(fun field ->
             `Assoc
               [ "name", `String field.name
               ; "value", encode_typed field.typ
               ; "nullable", `Bool field.nullable
               ]))
    in
    `Assoc
      [ "sql", `String entry.sql
      ; "kind", `String (kind_to_string entry.kind)
      ; "top_level_only", `Bool entry.top_level_only
      ; "parameters", `List (List.map entry.parameters ~f:encode_typed)
      ; "result", result
      ]
  in
  Yojson.Safe.pretty_to_string
    (`Assoc
        [ "version", `Int 2
        ; "role", `String t.role
        ; "search_path", `String t.search_path
        ; "queries", `List (List.map t.entries ~f:encode_entry)
        ])
  ^ "\n"
;;

exception Invalid of string

let invalid message = Stdlib.raise (Invalid message)

let identifier_exn value =
  match I.of_string value with
  | Ok value -> value
  | Error error -> invalid (I.error_to_string error)
;;

let member name json =
  match json with
  | `Assoc fields ->
    (match List.Assoc.find fields name ~equal:String.equal with
     | Some value -> value
     | None -> invalid ("missing query cache field: " ^ name))
  | _ -> invalid "expected a query cache object"
;;

let string_field json name = member name json |> J.to_string

let rec decode_type_exn depth json =
  if Int.(depth > 64) then
    invalid "query cache type nesting exceeds 64";
  let nested name = decode_type_exn (depth + 1) (member name json) in
  let kind =
    match string_field json "kind" with
    | "scalar" -> Type_info.Native_scalar
    | "enum" -> Native_enum (member "labels" json |> J.to_list |> List.map ~f:J.to_string)
    | "domain" -> Native_domain (nested "base")
    | "array" -> Native_array (nested "element")
    | "opaque" -> Native_opaque
    | kind -> invalid ("unsupported cached type kind: " ^ kind)
  in
  { Type_info.schema = identifier_exn (string_field json "schema")
  ; name = identifier_exn (string_field json "name")
  ; kind
  }
;;

let decode_typed_exn json = decode_type_exn 0 (member "type" json)

let of_string source =
  try
    let json = Yojson.Safe.from_string source in
    let version = member "version" json |> J.to_int in
    if not (Int.equal version 2) then
      invalid "unsupported query cache version";
    let entries =
      member "queries" json
      |> J.to_list
      |> List.map ~f:(fun json ->
        let result =
          match member "result" json with
          | `Null -> None
          | fields ->
            Some
              (J.to_list fields
               |> List.map ~f:(fun json ->
                 { name = string_field json "name"
                 ; typ = decode_typed_exn (member "value" json)
                 ; nullable = member "nullable" json |> J.to_bool
                 }))
        in
        let kind =
          match string_field json "kind" with
          | "select" -> Select
          | "returning" -> Returning
          | "command" -> Command
          | "unsupported" -> Unsupported
          | name -> invalid ("invalid cached statement kind: " ^ name)
        in
        let top_level_only = member "top_level_only" json |> J.to_bool in
        { sql = string_field json "sql"
        ; kind
        ; top_level_only
        ; parameters =
            member "parameters" json |> J.to_list |> List.map ~f:decode_typed_exn
        ; result
        })
    in
    create
      ~role:(string_field json "role")
      ~search_path:(string_field json "search_path")
      entries
  with
  | Invalid message | Yojson.Json_error message -> Error message
  | J.Type_error (message, _) -> Error ("invalid query cache: " ^ message)
;;

let codegen ~target t =
  let module_name =
    match target with
    | `Pgocaml_ppx -> "Typed_sql_pgocaml_ppx"
    | `Typed_sql_ppx -> "Typed_sql_ppx"
  in
  "open! Base\n\nlet () =\n  match "
  ^ module_name
  ^ ".Query_cache.of_string "
  ^ Printf.sprintf "%S" (to_string t)
  ^ " with\n  | Ok queries -> "
  ^ module_name
  ^ ".register_queries queries\n  | Error message -> failwith (\"embedded query cache invariant: \" ^ message)\n;;\n"
;;
