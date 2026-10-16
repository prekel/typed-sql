open! Base
module Type_info = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier
module J = Yojson.Safe.Util

type field =
  { name : string
  ; typ : Type_info.postgresql_type_info
  ; nullable : bool
  }

type entry =
  { sql : string
  ; parameters : Type_info.postgresql_type_info list
  ; result : field list option
  }

type t =
  { role : string
  ; search_path : string
  ; entries : entry list
  }

let codec typ =
  let open Result.Let_syntax in
  let%map native =
    Native_type.of_info ~offset:0 typ
    |> Result.map_error ~f:(fun error -> error.Sql.message)
  in
  Native_type.codec native
;;

let create ~role ~search_path entries =
  let open Result.Let_syntax in
  let entries = List.sort entries ~compare:(fun a b -> String.compare a.sql b.sql) in
  let%bind () =
    match
      List.find_consecutive_duplicate entries ~equal:(fun a b -> String.equal a.sql b.sql)
    with
    | Some _ -> Error "duplicate SQL in query cache"
    | None -> Ok ()
  in
  let%map () =
    List.fold_result entries ~init:() ~f:(fun () entry ->
      let%bind () =
        match entry.result with
        | Some [] -> Error "zero-column row results are not supported"
        | _ -> Ok ()
      in
      let types =
        entry.parameters
        @ Option.value_map entry.result ~default:[] ~f:(List.map ~f:(fun f -> f.typ))
      in
      List.fold_result types ~init:() ~f:(fun () typ ->
        let%map _ = codec typ in
        ()))
  in
  { role; search_path; entries }
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

let rec encode_codec = function
  | Codec.Scalar name -> `String name
  | Array element -> `Assoc [ "array", encode_codec element ]
;;

let encode_typed typ =
  match codec typ with
  | Ok codec -> `Assoc [ "type", encode_type typ; "codec", encode_codec codec ]
  | Error message -> failwith ("query cache invariant: " ^ message)
;;

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
      ; "parameters", `List (List.map entry.parameters ~f:encode_typed)
      ; "result", result
      ]
  in
  Yojson.Safe.pretty_to_string
    (`Assoc
        [ "version", `Int 1
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
    | kind -> invalid ("unsupported cached type kind: " ^ kind)
  in
  { Type_info.schema = identifier_exn (string_field json "schema")
  ; name = identifier_exn (string_field json "name")
  ; kind
  }
;;

let rec codec_matches expected json =
  match expected, json with
  | Codec.Scalar expected, `String actual -> String.equal expected actual
  | Array element, `Assoc [ ("array", actual) ] -> codec_matches element actual
  | _ -> false
;;

let decode_typed_exn ?(legacy = true) json =
  let typ = decode_type_exn 0 (member "type" json) in
  (match codec typ with
   | Error message -> invalid message
   | Ok expected ->
     if legacy && not (codec_matches expected (member "codec" json)) then
       invalid "cached codec does not match its PostgreSQL type");
  typ
;;

let of_string source =
  try
    let json = Yojson.Safe.from_string source in
    let version = member "version" json |> J.to_int in
    let decode_typed_exn json = decode_typed_exn ~legacy:(Int.equal version 1) json in
    if not (Int.equal version 1 || Int.equal version 2) then
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
        { sql = string_field json "sql"
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

let codegen t =
  "open! Base\n\nlet () =\n  match Typed_sql_pgocaml_ppx.Query_cache.of_string "
  ^ Printf.sprintf "%S" (to_string t)
  ^ " with\n  | Ok queries -> Typed_sql_pgocaml_ppx.register_queries queries\n  | Error message -> failwith (\"embedded query cache invariant: \" ^ message)\n;;\n"
;;

let plan t (query : Query_bind.t) =
  let fail message = Error { Sql.offset = 0; message } in
  let open Result.Let_syntax in
  let%bind entry =
    match List.find t.entries ~f:(fun entry -> String.equal entry.sql query.sql) with
    | Some entry -> Ok entry
    | None ->
      fail
        "query is absent from the cache; run typed-sql-pgocaml-queries prepare to refresh it"
  in
  let%bind pairs =
    match List.zip query.parameters entry.parameters with
    | Ok pairs -> Ok pairs
    | Unequal_lengths ->
      fail "cached parameter count does not match the quotation; refresh the query cache"
  in
  let to_codec typ =
    codec typ |> Result.map_error ~f:(fun message -> { Sql.offset = 0; message })
  in
  let%bind parameters =
    List.map pairs ~f:(fun (value, typ) ->
      let%map codec = to_codec typ in
      { Statement_plan.value; codec })
    |> Result.all
  in
  let%map result =
    match entry.result with
    | None -> Ok Statement_plan.Command
    | Some fields ->
      let%map fields =
        List.map fields ~f:(fun field ->
          let%map codec = to_codec field.typ in
          { Statement_plan.name = field.name; codec; nullable = field.nullable })
        |> Result.all
      in
      Statement_plan.Rows fields
  in
  { Statement_plan.sql = query.sql; parameters; result }
;;
