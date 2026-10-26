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
  ; queries : entry Map.M(String).t
  ; types : Type_info.postgresql_type_info Map.M(String).t
  }

let entries t = Map.data t.queries
let find t ~sql = Map.find t.queries sql

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

let identifier_key identifier =
  let name = I.to_string identifier in
  let first char = Char.is_lowercase char || Char.equal char '_' in
  if
    first name.[0]
    && String.for_all name ~f:(fun char ->
      first char || Char.is_digit char || Char.equal char '$')
  then
    name
  else
    "\"" ^ String.substr_replace_all name ~pattern:"\"" ~with_:"\"\"" ^ "\""
;;

let type_key (typ : Type_info.postgresql_type_info) =
  identifier_key typ.schema ^ "." ^ identifier_key typ.name
;;

let encode_type (typ : Type_info.postgresql_type_info) =
  let kind, nested =
    match typ.kind with
    | Native_scalar -> "scalar", []
    | Native_enum labels ->
      "enum", [ "labels", `List (List.map labels ~f:(fun label -> `String label)) ]
    | Native_domain base -> "domain", [ "base", `String (type_key base) ]
    | Native_array element -> "array", [ "element", `String (type_key element) ]
    | Native_opaque -> "opaque", []
  in
  `Assoc (("kind", `String kind) :: nested)
;;

let rec collect_type depth types (typ : Type_info.postgresql_type_info) =
  let open Result.Let_syntax in
  if Int.(depth > 64) then
    Error "query cache type nesting exceeds 64"
  else (
    let%bind types =
      match typ.kind with
      | Native_domain base | Native_array base -> collect_type (depth + 1) types base
      | Native_scalar | Native_enum _ | Native_opaque -> Ok types
    in
    let key = type_key typ in
    match Map.find types key with
    | None -> Ok (Map.set types ~key ~data:typ)
    | Some existing when Yojson.Safe.equal (encode_type existing) (encode_type typ) ->
      Ok types
    | Some _ -> Error ("conflicting query cache type definition: " ^ key))
;;

let create ~role ~search_path entries =
  let open Result.Let_syntax in
  let%bind queries =
    match
      Map.of_alist (module String) (List.map entries ~f:(fun entry -> entry.sql, entry))
    with
    | `Ok queries -> Ok queries
    | `Duplicate_key _ -> Error "duplicate SQL in query cache"
  in
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
  let%bind () =
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
      Ok ()
  in
  let%map types =
    List.fold_result
      entries
      ~init:(Map.empty (module String))
      ~f:(fun types entry ->
        let values =
          entry.parameters
          @ Option.value_map
              entry.result
              ~default:[]
              ~f:(List.map ~f:(fun field -> field.typ))
        in
        List.fold_result values ~init:types ~f:(collect_type 0))
  in
  { role; search_path; queries; types }
;;

let encode_entry entry =
  let result =
    match entry.result with
    | None -> `Null
    | Some fields ->
      `List
        (List.map fields ~f:(fun field ->
           `Assoc
             [ "name", `String field.name
             ; "type", `String (type_key field.typ)
             ; "nullable", `Bool field.nullable
             ]))
  in
  `Assoc
    [ "sql", `String entry.sql
    ; "kind", `String (kind_to_string entry.kind)
    ; "top_level_only", `Bool entry.top_level_only
    ; ( "parameters"
      , `List (List.map entry.parameters ~f:(fun typ -> `String (type_key typ))) )
    ; "result", result
    ]
;;

let encode_types t =
  Map.to_alist t.types |> List.map ~f:(fun (key, typ) -> key, encode_type typ)
;;

let to_json t =
  `Assoc
    [ "version", `Int 3
    ; "role", `String t.role
    ; "search_path", `String t.search_path
    ; "types", `Assoc (encode_types t)
    ; "queries", `List (List.map (entries t) ~f:encode_entry)
    ]
;;

let rec inline_json = function
  | `Assoc fields ->
    "{"
    ^ String.concat
        ~sep:", "
        (List.map fields ~f:(fun (name, value) ->
           Yojson.Safe.to_string (`String name) ^ ": " ^ inline_json value))
    ^ "}"
  | `List values -> "[" ^ String.concat ~sep:", " (List.map values ~f:inline_json) ^ "]"
  | value -> Yojson.Safe.to_string value
;;

let to_string t =
  let render_entry entry =
    let fields =
      match encode_entry entry with
      | `Assoc fields -> fields
      | _ -> failwith "query cache invariant: encoded entry is not an object"
    in
    let lines =
      List.map fields ~f:(fun (name, value) ->
        let value =
          match name, value with
          | "result", `List fields ->
            "[\n"
            ^ String.concat
                ~sep:",\n"
                (List.map fields ~f:(fun field -> "        " ^ inline_json field))
            ^ "\n      ]"
          | _ -> inline_json value
        in
        "      " ^ inline_json (`String name) ^ ": " ^ value)
    in
    "    {\n" ^ String.concat ~sep:",\n" lines ^ "\n    }"
  in
  let types =
    encode_types t
    |> List.map ~f:(fun (name, definition) ->
      "    " ^ inline_json (`String name) ^ ": " ^ inline_json definition)
  in
  let object_body = function
    | [] -> "{}"
    | lines -> "{\n" ^ String.concat ~sep:",\n" lines ^ "\n  }"
  in
  let queries =
    match entries t with
    | [] -> "[]"
    | entries ->
      "[\n" ^ String.concat ~sep:",\n" (List.map entries ~f:render_entry) ^ "\n  ]"
  in
  "{\n  \"version\": 3,\n  \"role\": "
  ^ inline_json (`String t.role)
  ^ ",\n  \"search_path\": "
  ^ inline_json (`String t.search_path)
  ^ ",\n  \"types\": "
  ^ object_body types
  ^ ",\n  \"queries\": "
  ^ queries
  ^ "\n}\n"
;;

exception Invalid of string

let invalid message = Stdlib.raise (Invalid message)

let identifier_exn value =
  match I.of_string value with
  | Ok value -> value
  | Error error -> invalid (I.error_to_string error)
;;

let member name = function
  | `Assoc fields ->
    (match List.Assoc.find fields name ~equal:String.equal with
     | Some value -> value
     | None -> invalid ("missing query cache field: " ^ name))
  | _ -> invalid "expected a query cache object"
;;

let string_field json name = member name json |> J.to_string

let decode_type_key_exn key =
  let length = String.length key in
  let malformed () = invalid ("invalid query cache type key: " ^ key) in
  let identifier start =
    if Int.(start >= length) then
      malformed ();
    if Char.equal key.[start] '"' then (
      let buffer = Buffer.create 16 in
      let rec loop position =
        if Int.(position >= length) then
          malformed ();
        match key.[position] with
        | '"' when Int.(position + 1 < length) && Char.equal key.[position + 1] '"' ->
          Buffer.add_char buffer '"';
          loop (position + 2)
        | '"' -> identifier_exn (Buffer.contents buffer), position + 1
        | char ->
          Buffer.add_char buffer char;
          loop (position + 1)
      in
      loop (start + 1))
    else (
      let stop = Option.value (String.index_from key start '.') ~default:length in
      identifier_exn (String.sub key ~pos:start ~len:(stop - start)), stop)
  in
  let schema, separator = identifier 0 in
  if Int.(separator >= length) || not (Char.equal key.[separator] '.') then
    malformed ();
  let name, stop = identifier (separator + 1) in
  if
    (not (Int.equal stop length))
    || not (String.equal key (identifier_key schema ^ "." ^ identifier_key name))
  then
    malformed ();
  schema, name
;;

let decode_types_exn json =
  let definitions =
    match member "types" json with
    | `Assoc definitions ->
      (match Map.of_alist (module String) definitions with
       | `Ok definitions ->
         Map.mapi definitions ~f:(fun ~key ~data -> decode_type_key_exn key, data)
       | `Duplicate_key key -> invalid ("duplicate query cache type definition: " ^ key))
    | _ -> invalid "expected a query cache type dictionary"
  in
  let rec resolve depth visiting resolved key =
    if Int.(depth > 64) then
      invalid "query cache type nesting exceeds 64";
    match Map.find resolved key with
    | Some (typ, height) ->
      if Int.(depth + height > 64) then
        invalid "query cache type nesting exceeds 64";
      typ, height, resolved
    | None ->
      if Set.mem visiting key then
        invalid ("cyclic query cache type reference: " ^ key);
      let (schema, name), definition =
        match Map.find definitions key with
        | Some definition -> definition
        | None -> invalid ("unknown query cache type reference: " ^ key)
      in
      let nested field =
        resolve
          (depth + 1)
          (Set.add visiting key)
          resolved
          (string_field definition field)
      in
      let kind, height, resolved =
        match string_field definition "kind" with
        | "scalar" -> Type_info.Native_scalar, 0, resolved
        | "opaque" -> Native_opaque, 0, resolved
        | "enum" ->
          ( Native_enum
              (member "labels" definition |> J.to_list |> List.map ~f:J.to_string)
          , 0
          , resolved )
        | "domain" ->
          let typ, height, resolved = nested "base" in
          Native_domain typ, height + 1, resolved
        | "array" ->
          let typ, height, resolved = nested "element" in
          Native_array typ, height + 1, resolved
        | kind -> invalid ("unsupported cached type kind: " ^ kind)
      in
      let typ = { Type_info.schema; name; kind } in
      typ, height, Map.set resolved ~key ~data:(typ, height)
  in
  Map.fold
    definitions
    ~init:(Map.empty (module String))
    ~f:(fun ~key ~data:_ resolved ->
      let _, _, resolved = resolve 0 (Set.empty (module String)) resolved key in
      resolved)
  |> Map.map ~f:fst
;;

let of_string source =
  try
    let json = Yojson.Safe.from_string source in
    if not (Int.equal (member "version" json |> J.to_int) 3) then
      invalid "unsupported query cache version";
    let types = decode_types_exn json in
    let reference json =
      let key = J.to_string json in
      match Map.find types key with
      | Some typ -> typ
      | None -> invalid ("unknown query cache type reference: " ^ key)
    in
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
                 ; typ = reference (member "type" json)
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
        { sql = string_field json "sql"
        ; kind
        ; top_level_only = member "top_level_only" json |> J.to_bool
        ; parameters = member "parameters" json |> J.to_list |> List.map ~f:reference
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
  ^ Printf.sprintf "%S" (Yojson.Safe.to_string (to_json t))
  ^ " with\n  | Ok queries -> "
  ^ module_name
  ^ ".register_queries queries\n  | Error message -> failwith (\"embedded query cache invariant: \" ^ message)\n;;\n"
;;
