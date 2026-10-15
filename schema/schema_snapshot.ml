open! Base
module Identifier = Typed_sql.Identifier

type error = string

let error_to_string error = error
let fail path message = Error (path ^ ": " ^ message)

type 'a codec =
  { encode : 'a -> Yojson.Safe.t
  ; decode : string -> Yojson.Safe.t -> ('a, error) Result.t
  }

let string =
  { encode = (fun value -> `String value)
  ; decode =
      (fun path -> function
         | `String value -> Ok value
         | _ -> fail path "expected string")
  }
;;

let bool =
  { encode = (fun value -> `Bool value)
  ; decode =
      (fun path -> function
         | `Bool value -> Ok value
         | _ -> fail path "expected boolean")
  }
;;

let int =
  { encode = (fun value -> `Int value)
  ; decode =
      (fun path -> function
         | `Int value -> Ok value
         | _ -> fail path "expected integer")
  }
;;

let identifier =
  { encode = (fun value -> string.encode (Identifier.to_string value))
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind value = string.decode path json in
        Identifier.of_string value
        |> Result.map_error ~f:(fun error ->
          path ^ ": " ^ Identifier.error_to_string error))
  }
;;

let option codec =
  { encode =
      (function
        | None -> `Null
        | Some value -> codec.encode value)
  ; decode =
      (fun path -> function
         | `Null -> Ok None
         | value -> Result.map (codec.decode path value) ~f:Option.some)
  }
;;

let list codec =
  { encode = (fun values -> `List (List.map values ~f:codec.encode))
  ; decode =
      (fun path -> function
         | `List values ->
           List.mapi values ~f:(fun index value ->
             codec.decode (path ^ "[" ^ Int.to_string index ^ "]") value)
           |> Result.all
         | _ -> fail path "expected array")
  }
;;

let object_fields path = function
  | `Assoc fields ->
    let rec check seen = function
      | [] -> Ok fields
      | (name, _) :: rest ->
        if List.mem seen name ~equal:String.equal then
          fail (path ^ "." ^ name) "duplicate field"
        else
          check (name :: seen) rest
    in
    check [] fields
  | _ -> fail path "expected object"
;;

let known_fields path names fields =
  match
    List.find fields ~f:(fun (name, _) -> not (List.mem names name ~equal:String.equal))
  with
  | Some (name, _) -> fail (path ^ "." ^ name) "unknown field"
  | None -> Ok ()
;;

let field path fields name codec =
  let path = path ^ "." ^ name in
  match List.Assoc.find fields name ~equal:String.equal with
  | None -> fail path "missing field"
  | Some value -> codec.decode path value
;;

let rec db_type =
  let types =
    [ "bool", Schema_ir.Bool
    ; "int", Schema_ir.Int
    ; "int64", Schema_ir.Int64
    ; "float", Schema_ir.Float
    ; "numeric", Schema_ir.Numeric
    ; "text", Schema_ir.Text
    ; "bytes", Schema_ir.Bytes
    ; "date", Schema_ir.Date
    ; "timestamp", Schema_ir.Timestamp
    ; "timestamp_without_timezone", Schema_ir.Timestamp_without_timezone
    ; "interval", Schema_ir.Interval
    ; "json", Schema_ir.Json
    ; "jsonb", Schema_ir.Jsonb
    ; "uuid", Schema_ir.Uuid
    ]
  in
  { encode =
      (fun value ->
        let kind, extra =
          match value with
          | Schema_ir.Bool -> "bool", []
          | Int -> "int", []
          | Int64 -> "int64", []
          | Float -> "float", []
          | Numeric -> "numeric", []
          | Text -> "text", []
          | Bytes -> "bytes", []
          | Date -> "date", []
          | Timestamp -> "timestamp", []
          | Timestamp_without_timezone -> "timestamp_without_timezone", []
          | Interval -> "interval", []
          | Json -> "json", []
          | Jsonb -> "jsonb", []
          | Uuid -> "uuid", []
          | Enum { schema; name; labels } ->
            ( "enum"
            , [ "schema", identifier.encode schema
              ; "name", identifier.encode name
              ; "labels", (list string).encode labels
              ] )
          | Domain { schema; name; base } ->
            ( "domain"
            , [ "schema", identifier.encode schema
              ; "name", identifier.encode name
              ; "base", db_type.encode base
              ] )
          | Array element -> "array", [ "element", db_type.encode element ]
          | Named { schema; name } ->
            ( "named"
            , [ "schema", identifier.encode schema; "name", identifier.encode name ] )
          | Unsupported name -> "unsupported", [ "database_type", string.encode name ]
        in
        `Assoc (("kind", string.encode kind) :: extra))
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind fields = object_fields path json in
        let%bind kind = field path fields "kind" string in
        match kind with
        | "unsupported" ->
          let%bind () = known_fields path [ "kind"; "database_type" ] fields in
          let%map name = field path fields "database_type" string in
          Schema_ir.Unsupported name
        | "array" ->
          let%bind () = known_fields path [ "kind"; "element" ] fields in
          let%map element = field path fields "element" db_type in
          Schema_ir.Array element
        | "enum" ->
          let%bind () = known_fields path [ "kind"; "schema"; "name"; "labels" ] fields in
          let%bind schema = field path fields "schema" identifier in
          let%bind name = field path fields "name" identifier in
          let%map labels = field path fields "labels" (list string) in
          Schema_ir.Enum { schema; name; labels }
        | "domain" ->
          let%bind () = known_fields path [ "kind"; "schema"; "name"; "base" ] fields in
          let%bind schema = field path fields "schema" identifier in
          let%bind name = field path fields "name" identifier in
          let%map base = field path fields "base" db_type in
          Schema_ir.Domain { schema; name; base }
        | "named" ->
          let%bind () = known_fields path [ "kind"; "schema"; "name" ] fields in
          let%bind schema = field path fields "schema" identifier in
          let%map name = field path fields "name" identifier in
          Schema_ir.Named { schema; name }
        | _ ->
          let%bind () = known_fields path [ "kind" ] fields in
          (match List.Assoc.find types kind ~equal:String.equal with
           | Some value -> Ok value
           | None -> fail (path ^ ".kind") ("unknown database type: " ^ kind)))
  }
;;

let postgresql_type =
  { encode =
      (fun (schema, name) ->
        `Assoc [ "schema", identifier.encode schema; "name", identifier.encode name ])
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind fields = object_fields path json in
        let%bind () = known_fields path [ "schema"; "name" ] fields in
        let%bind schema = field path fields "schema" identifier in
        let%map name = field path fields "name" identifier in
        schema, name)
  }
;;

let rec postgresql_type_info =
  { encode =
      (fun (value : Schema_ir.postgresql_type_info) ->
        let kind, extra =
          match value.kind with
          | Native_scalar -> "scalar", []
          | Schema_ir.Native_opaque -> "opaque", []
          | Schema_ir.Native_enum labels ->
            "enum", [ "labels", (list string).encode labels ]
          | Schema_ir.Native_domain base ->
            "domain", [ "base", postgresql_type_info.encode base ]
          | Schema_ir.Native_array element ->
            "array", [ "element", postgresql_type_info.encode element ]
        in
        `Assoc
          ([ "schema", identifier.encode value.schema
           ; "name", identifier.encode value.name
           ; "kind", string.encode kind
           ]
           @ extra))
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind fields = object_fields path json in
        let%bind schema = field path fields "schema" identifier in
        let%bind name = field path fields "name" identifier in
        let%bind kind = field path fields "kind" string in
        let%bind extra, kind =
          match kind with
          | "scalar" -> Ok ([], Schema_ir.Native_scalar)
          | "opaque" -> Ok ([], Schema_ir.Native_opaque)
          | "enum" ->
            let%map labels = field path fields "labels" (list string) in
            [ "labels" ], Schema_ir.Native_enum labels
          | "domain" ->
            let%map base = field path fields "base" postgresql_type_info in
            [ "base" ], Schema_ir.Native_domain base
          | "array" ->
            let%map element = field path fields "element" postgresql_type_info in
            [ "element" ], Schema_ir.Native_array element
          | _ -> fail (path ^ ".kind") "unknown native type kind"
        in
        let%map () = known_fields path ([ "schema"; "name"; "kind" ] @ extra) fields in
        { Schema_ir.schema; name; kind })
  }
;;

let optional_field path fields name codec =
  match List.Assoc.find fields name ~equal:String.equal with
  | None -> Ok None
  | Some json -> (option codec).decode (path ^ "." ^ name) json
;;

let column version =
  { encode =
      (fun (value : Schema_ir.column) ->
        `Assoc
          ([ "name", identifier.encode value.name
           ; "db_type", db_type.encode value.db_type
           ; "nullable", bool.encode value.nullable
           ; "default", (option string).encode value.default
           ; "generated", bool.encode value.generated
           ; "primary_key_position", (option int).encode value.primary_key_position
           ; "postgresql_type", (option postgresql_type).encode value.postgresql_type
           ]
           @ Option.value_map value.postgresql_type_info ~default:[] ~f:(fun info ->
             [ "postgresql_type_info", postgresql_type_info.encode info ])
           @ Option.value_map
               value.postgresql_attribute_not_null
               ~default:[]
               ~f:(fun flag -> [ "postgresql_attribute_not_null", bool.encode flag ])
           @ Option.value_map
               value.postgresql_type_modifier
               ~default:[]
               ~f:(fun modifier -> [ "postgresql_type_modifier", int.encode modifier ])))
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind fields = object_fields path json in
        let%bind () =
          known_fields
            path
            ([ "name"
             ; "db_type"
             ; "nullable"
             ; "default"
             ; "generated"
             ; "primary_key_position"
             ]
             @
             if Int.(version = 3) then
               [ "postgresql_type"
               ; "postgresql_type_info"
               ; "postgresql_attribute_not_null"
               ; "postgresql_type_modifier"
               ]
             else
               [])
            fields
        in
        let%bind name = field path fields "name" identifier in
        let%bind db_type = field path fields "db_type" db_type in
        let%bind nullable = field path fields "nullable" bool in
        let%bind default = field path fields "default" (option string) in
        let%bind generated = field path fields "generated" bool in
        let%bind primary_key_position =
          field path fields "primary_key_position" (option int)
        in
        let%bind postgresql_type =
          if Int.(version = 3) then
            field path fields "postgresql_type" (option postgresql_type)
          else
            Ok None
        in
        let%bind postgresql_type_info =
          if Int.(version = 3) then
            optional_field path fields "postgresql_type_info" postgresql_type_info
          else
            Ok None
        in
        let%bind () =
          match postgresql_type, postgresql_type_info with
          | Some (schema, name), Some info
            when String.equal
                   (Identifier.to_string schema)
                   (Identifier.to_string info.schema)
                 && String.equal
                      (Identifier.to_string name)
                      (Identifier.to_string info.name) -> Ok ()
          | _, None -> Ok ()
          | _ ->
            fail
              (path ^ ".postgresql_type_info")
              "native type tree does not match postgresql_type"
        in
        let%bind postgresql_attribute_not_null =
          if Int.(version = 3) then
            optional_field path fields "postgresql_attribute_not_null" bool
          else
            Ok None
        in
        let%bind postgresql_type_modifier =
          if Int.(version = 3) then
            optional_field path fields "postgresql_type_modifier" int
          else
            Ok None
        in
        let%map () =
          match postgresql_type_modifier with
          | Some modifier when Int.(modifier < -2147483648 || modifier > 2147483647) ->
            fail
              (path ^ ".postgresql_type_modifier")
              "expected a signed 32-bit type modifier"
          | _ -> Ok ()
        in
        Schema_ir.column
          ~name
          ~db_type
          ~nullable
          ?default
          ~generated
          ?primary_key_position
          ?postgresql_type
          ?postgresql_type_info
          ?postgresql_attribute_not_null
          ?postgresql_type_modifier
          ())
  }
;;

let foreign_key =
  { encode =
      (fun (value : Schema_ir.foreign_key) ->
        `Assoc
          [ "columns", (list identifier).encode value.columns
          ; "referenced_schema", (option identifier).encode value.referenced_schema
          ; "referenced_table", identifier.encode value.referenced_table
          ; "referenced_columns", (list identifier).encode value.referenced_columns
          ])
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind fields = object_fields path json in
        let%bind () =
          known_fields
            path
            [ "columns"; "referenced_schema"; "referenced_table"; "referenced_columns" ]
            fields
        in
        let%bind columns = field path fields "columns" (list identifier) in
        let%bind referenced_schema =
          field path fields "referenced_schema" (option identifier)
        in
        let%bind referenced_table = field path fields "referenced_table" identifier in
        let%map referenced_columns =
          field path fields "referenced_columns" (list identifier)
        in
        Schema_ir.foreign_key
          ~columns
          ?referenced_schema
          ~referenced_table
          ~referenced_columns
          ())
  }
;;

let unique_constraint =
  { encode =
      (fun (value : Schema_ir.unique_constraint) ->
        `Assoc
          [ "name", (option identifier).encode value.name
          ; "columns", (list identifier).encode value.columns
          ])
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind fields = object_fields path json in
        let%bind () = known_fields path [ "name"; "columns" ] fields in
        let%bind name = field path fields "name" (option identifier) in
        let%map columns = field path fields "columns" (list identifier) in
        Schema_ir.unique_constraint ?name columns)
  }
;;

let table version =
  { encode =
      (fun (value : Schema_ir.table) ->
        `Assoc
          ([ "schema", (option identifier).encode value.schema
           ; "name", identifier.encode value.name
           ; "columns", (list (column version)).encode value.columns
           ; "foreign_keys", (list foreign_key).encode value.foreign_keys
           ; ( "unique_constraints"
             , (list unique_constraint).encode value.unique_constraints )
           ]
           @
           match value.postgresql_primary_key_deferrable with
           | None -> []
           | Some flag -> [ "postgresql_primary_key_deferrable", `Bool flag ]))
  ; decode =
      (fun path json ->
        let open Result.Let_syntax in
        let%bind fields = object_fields path json in
        let%bind () =
          known_fields
            path
            ([ "schema"; "name"; "columns"; "foreign_keys"; "unique_constraints" ]
             @
             if Int.equal version 3 then
               [ "postgresql_primary_key_deferrable" ]
             else
               [])
            fields
        in
        let%bind schema = field path fields "schema" (option identifier) in
        let%bind name = field path fields "name" identifier in
        let%bind columns = field path fields "columns" (list (column version)) in
        let%bind foreign_keys = field path fields "foreign_keys" (list foreign_key) in
        let%bind unique_constraints =
          field path fields "unique_constraints" (list unique_constraint)
        in
        let%map postgresql_primary_key_deferrable =
          match
            List.Assoc.find fields "postgresql_primary_key_deferrable" ~equal:String.equal
          with
          | None -> Ok None
          | Some json ->
            (option bool).decode (path ^ ".postgresql_primary_key_deferrable") json
        in
        Schema_ir.table
          ?schema
          ~name
          ~columns
          ~foreign_keys
          ~unique_constraints
          ?postgresql_primary_key_deferrable
          ())
  }
;;

let to_string schema =
  `Assoc
    [ "version", `Int 3; "tables", (list (table 3)).encode (Schema_ir.tables schema) ]
  |> Yojson.Safe.pretty_to_string ~std:true
  |> fun json -> json ^ "\n"
;;

let of_string source =
  let open Result.Let_syntax in
  let%bind json =
    try Ok (Yojson.Safe.from_string source) with
    | Yojson.Json_error message -> fail "$" ("invalid JSON: " ^ message)
  in
  let%bind fields = object_fields "$" json in
  let%bind () = known_fields "$" [ "version"; "tables" ] fields in
  let%bind version = field "$" fields "version" int in
  if not Int.(version = 2 || version = 3) then
    fail "$.version" ("unsupported snapshot version: " ^ Int.to_string version)
  else (
    let%map tables = field "$" fields "tables" (list (table version)) in
    Schema_ir.v tables)
;;
