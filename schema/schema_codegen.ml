open! Base
module Identifier = Typed_sql.Identifier

type error =
  | Empty_table of Identifier.t
  | Unsupported_type of
      { table : Identifier.t
      ; column : Identifier.t
      ; database_type : string
      }
  | Invalid_rules of string

let error_to_string = function
  | Empty_table table -> "table " ^ Identifier.to_string table ^ " has no columns"
  | Unsupported_type { table; column; database_type } ->
    String.concat
      [ "unsupported type "
      ; database_type
      ; " for "
      ; Identifier.to_string table
      ; "."
      ; Identifier.to_string column
      ]
  | Invalid_rules message -> "invalid type rules: " ^ message
;;

type rule =
  { priority : int
  ; sql_type : string option
  ; column : string option
  ; module_path : string
  }

let rules_of_string source =
  let fail message = Error message in
  let fields = function
    | `Assoc fields -> Ok fields
    | _ -> fail "expected object"
  in
  let get fields key =
    match List.Assoc.find fields key ~equal:String.equal with
    | Some value -> Ok value
    | None -> fail ("missing " ^ key)
  in
  let get_string = function
    | `String value -> Ok value
    | _ -> fail "expected string"
  in
  let get_optional_string = function
    | `Null -> Ok None
    | `String value -> Ok (Some value)
    | _ -> fail "expected string or null"
  in
  let valid_module_path path =
    String.split path ~on:'.'
    |> List.for_all ~f:(fun part ->
      Int.(String.length part > 0)
      && Char.is_uppercase part.[0]
      && String.for_all part ~f:(fun character ->
        Char.is_alphanum character || Char.equal character '_'))
  in
  let validate_pattern pattern =
    match pattern with
    | None -> Ok ()
    | Some pattern ->
      (try
         ignore (Str.regexp pattern);
         Ok ()
       with
       | Failure message -> fail ("invalid regexp: " ^ message))
  in
  let decode_rule json =
    let open Result.Let_syntax in
    let%bind fields = fields json in
    let names = List.map fields ~f:fst in
    let allowed = [ "priority"; "sql_type"; "column"; "module" ] in
    let%bind () =
      if
        List.length names
        <> List.length (List.dedup_and_sort names ~compare:String.compare)
        || List.exists names ~f:(fun name ->
          not (List.mem allowed name ~equal:String.equal))
      then
        fail "duplicate or unknown rule field"
      else
        Ok ()
    in
    let%bind priority =
      let%bind value = get fields "priority" in
      match value with
      | `Int value -> Ok value
      | _ -> fail "priority must be an integer"
    in
    let%bind sql_type =
      let%bind value = get fields "sql_type" in
      get_optional_string value
    in
    let%bind column =
      let%bind value = get fields "column" in
      get_optional_string value
    in
    let%bind module_path =
      let%bind value = get fields "module" in
      get_string value
    in
    let%bind () =
      if Option.is_none sql_type && Option.is_none column then
        fail "rule needs sql_type or column"
      else if not (valid_module_path module_path) then
        fail ("invalid OCaml module path: " ^ module_path)
      else
        Ok ()
    in
    let%bind () = validate_pattern sql_type in
    let%map () = validate_pattern column in
    { priority; sql_type; column; module_path }
  in
  try
    let open Result.Let_syntax in
    let%bind json = fields (Yojson.Safe.from_string source) in
    let%bind version = get json "version" in
    let%bind () =
      match version with
      | `Int 1 -> Ok ()
      | _ -> fail "unsupported rules version"
    in
    let%bind rules = get json "rules" in
    let%map rules =
      match rules with
      | `List rules -> Result.all (List.map rules ~f:decode_rule)
      | _ -> fail "rules must be an array"
    in
    List.mapi rules ~f:(fun index rule -> index, rule)
    |> List.sort ~compare:(fun (left_index, left) (right_index, right) ->
      let priority = Int.compare right.priority left.priority in
      if Int.(priority = 0) then
        Int.compare left_index right_index
      else
        priority)
    |> List.map ~f:snd
  with
  | Yojson.Json_error message -> fail ("invalid JSON: " ^ message)
;;

let keywords =
  [ "and"
  ; "as"
  ; "assert"
  ; "begin"
  ; "class"
  ; "constraint"
  ; "do"
  ; "done"
  ; "downto"
  ; "else"
  ; "end"
  ; "exception"
  ; "external"
  ; "false"
  ; "for"
  ; "fun"
  ; "function"
  ; "functor"
  ; "if"
  ; "in"
  ; "include"
  ; "inherit"
  ; "initializer"
  ; "lazy"
  ; "let"
  ; "match"
  ; "method"
  ; "module"
  ; "mutable"
  ; "new"
  ; "nonrec"
  ; "object"
  ; "of"
  ; "open"
  ; "or"
  ; "private"
  ; "rec"
  ; "sig"
  ; "struct"
  ; "then"
  ; "to"
  ; "true"
  ; "try"
  ; "type"
  ; "val"
  ; "virtual"
  ; "when"
  ; "while"
  ; "with"
  ; "asr"
  ; "land"
  ; "lor"
  ; "lsl"
  ; "lsr"
  ; "lxor"
  ; "mod"
  ; "effect"
  ; "continue"
  ; "perform"
  ; "public"
  ]
;;

let identifier value =
  let value =
    String.map value ~f:(fun character ->
      if Char.is_alpha character || Char.is_digit character || Char.equal character '_'
      then
        character
      else
        '_')
  in
  let value = String.lowercase value in
  let value =
    if String.for_all value ~f:(Char.equal '_') then
      "field"
    else
      value
  in
  let value =
    match value.[0] with
    | '0' .. '9' -> "_" ^ value
    | _ -> value
  in
  if List.mem keywords value ~equal:String.equal then
    value ^ "_"
  else
    value
;;

let normalized_module_name value =
  let value = identifier value in
  if Char.is_alpha value.[0] then
    String.capitalize value
  else
    "Generated" ^ value
;;

let fresh_name ~used ~bindings base =
  let rec find suffix =
    let candidate =
      if Int.(suffix = 1) then
        base
      else
        base ^ "_" ^ Int.to_string suffix
    in
    let names = bindings candidate in
    if List.exists names ~f:(fun name -> List.mem used name ~equal:String.equal) then
      find (suffix + 1)
    else
      candidate, names @ used
  in
  find 1
;;

let column_bindings name =
  [ name
  ; name ^ "_column"
  ; name ^ "_has_default"
  ; name ^ "_default"
  ; name ^ "_is_generated"
  ; name ^ "_primary_key_position"
  ]
;;

let allocate_column_names (columns : Schema_ir.column list) =
  let reserved =
    [ "table"
    ; "projection"
    ; "foreign_keys"
    ; "unique_constraints"
    ; "table_ref"
    ; "return"
    ; "map"
    ; "both"
    ; "apply"
    ; "all"
    ]
  in
  let rec loop used allocated = function
    | [] -> List.rev allocated
    | (column : Schema_ir.column) :: rest ->
      let name, used =
        fresh_name
          ~used
          ~bindings:column_bindings
          (identifier (Identifier.to_string column.Schema_ir.name))
      in
      loop used ((column, name) :: allocated) rest
  in
  loop reserved [] columns
;;

let allocate_module_names (tables : Schema_ir.table list) =
  let rec loop used allocated = function
    | [] -> List.rev allocated
    | (table : Schema_ir.table) :: rest ->
      let name, used =
        fresh_name
          ~used
          ~bindings:(fun name -> [ name ])
          (normalized_module_name (Identifier.to_string table.Schema_ir.name))
      in
      loop used ((table, name) :: allocated) rest
  in
  loop
    [ "Typed_sql_codegen"; "Typed_sql_codegen_ptime"; "Typed_sql_generated_types" ]
    []
    tables
;;

let qualified_name schema name =
  Identifier.to_string schema ^ "." ^ Identifier.to_string name
;;

let rec sql_type_name = function
  | Schema_ir.Bool -> "boolean"
  | Int -> "integer"
  | Int64 -> "bigint"
  | Float -> "double precision"
  | Numeric -> "numeric"
  | Text -> "text"
  | Bytes -> "bytea"
  | Date -> "date"
  | Timestamp -> "timestamp with time zone"
  | Timestamp_without_timezone -> "timestamp without time zone"
  | Interval -> "interval"
  | Json -> "json"
  | Jsonb -> "jsonb"
  | Uuid -> "uuid"
  | Enum { schema; name; _ } | Domain { schema; name; _ } | Named { schema; name } ->
    qualified_name schema name
  | Array element -> sql_type_name element ^ "[]"
  | Unsupported name -> name
;;

let matches pattern value =
  match pattern with
  | None -> true
  | Some pattern ->
    let regexp = Str.regexp pattern in
    Str.string_match regexp value 0 && Int.(Str.match_end () = String.length value)
;;

let find_rule rules ~sql_type ~column =
  List.find rules ~f:(fun rule ->
    matches rule.sql_type sql_type
    &&
    match rule.column, column with
    | None, _ -> true
    | Some pattern, Some column -> matches (Some pattern) column
    | Some _, None -> false)
;;

let module_key = function
  | Schema_ir.Enum { schema; name; _ } | Domain { schema; name; _ } ->
    qualified_name schema name
  | _ -> ""
;;

let collect_types rules schema =
  let rec add ~column seen typ =
    let sql_type = sql_type_name typ in
    if Option.is_some (find_rule rules ~sql_type ~column) then
      seen
    else (
      match
        typ
      with
      | Schema_ir.Enum _ ->
        let key = module_key typ in
        if List.exists seen ~f:(fun candidate -> String.equal (module_key candidate) key)
        then
          seen
        else
          seen @ [ typ ]
      | Schema_ir.Domain { base; _ } ->
        let seen = add ~column:None seen base in
        let key = module_key typ in
        if List.exists seen ~f:(fun candidate -> String.equal (module_key candidate) key)
        then
          seen
        else
          seen @ [ typ ]
      | Schema_ir.Array element -> add ~column:None seen element
      | _ -> seen)
  in
  List.fold (Schema_ir.tables schema) ~init:[] ~f:(fun seen table ->
    List.fold table.Schema_ir.columns ~init:seen ~f:(fun seen column ->
      let full_name =
        (match table.schema with
         | None -> ""
         | Some schema -> Identifier.to_string schema ^ ".")
        ^ Identifier.to_string table.name
        ^ "."
        ^ Identifier.to_string column.name
      in
      add ~column:(Some full_name) seen column.db_type))
;;

let type_module_names types =
  let rec loop used result = function
    | [] -> List.rev result
    | typ :: rest ->
      let key = module_key typ in
      let base = normalized_module_name ("type_" ^ key) in
      let name, used = fresh_name ~used ~bindings:(fun name -> [ name ]) base in
      loop used ((key, name) :: result) rest
  in
  loop [] [] types
;;

let rec type_source ~rules ~types ~column typ =
  let sql_type = sql_type_name typ in
  match find_rule rules ~sql_type ~column with
  | Some rule -> Ok (rule.module_path ^ ".t", rule.module_path ^ ".db_type")
  | None ->
    (match typ with
     | Schema_ir.Bool -> Ok ("bool", "Typed_sql_codegen.Db_type.bool")
     | Int -> Ok ("int", "Typed_sql_codegen.Db_type.int")
     | Int64 -> Ok ("int64", "Typed_sql_codegen.Db_type.int64")
     | Float -> Ok ("float", "Typed_sql_codegen.Db_type.float")
     | Numeric -> Ok ("Typed_sql_codegen.Decimal.t", "Typed_sql_codegen.Db_type.numeric")
     | Text -> Ok ("string", "Typed_sql_codegen.Db_type.text")
     | Bytes -> Ok ("bytes", "Typed_sql_codegen.Db_type.bytes")
     | Date -> Ok ("Typed_sql_codegen.Date.t", "Typed_sql_codegen.Db_type.date")
     | Timestamp -> Ok ("Typed_sql_codegen_ptime.t", "Typed_sql_codegen.Db_type.timestamp")
     | Timestamp_without_timezone ->
       Ok
         ( "Typed_sql_codegen.Local_timestamp.t"
         , "Typed_sql_codegen.Db_type.Postgresql.local_timestamp" )
     | Interval ->
       Ok ("Typed_sql_codegen.Interval.t", "Typed_sql_codegen.Db_type.Postgresql.interval")
     | Json -> Ok ("Yojson.Safe.t", "Typed_sql_codegen.Db_type.Postgresql.json")
     | Jsonb -> Ok ("Yojson.Safe.t", "Typed_sql_codegen.Db_type.Postgresql.jsonb")
     | Uuid -> Ok ("Typed_sql_codegen.Uuid.t", "Typed_sql_codegen.Db_type.uuid")
     | Array element ->
       let open Result.Let_syntax in
       let%map ocaml_type, descriptor = type_source ~rules ~types ~column:None element in
       ( ocaml_type ^ " Typed_sql_codegen.Pg_array.t"
       , "Typed_sql_codegen.Db_type.Postgresql.array (" ^ descriptor ^ ")" )
     | Enum _ | Domain _ ->
       (match List.Assoc.find types (module_key typ) ~equal:String.equal with
        | Some name ->
          let path = "Typed_sql_generated_types." ^ name in
          Ok (path ^ ".t", path ^ ".db_type")
        | None -> Error sql_type)
     | Named _ | Unsupported _ -> Error sql_type)
;;

let quoted value = Printf.sprintf "%S" (Identifier.to_string value)

let quoted_option = function
  | None -> "None"
  | Some value -> "Some " ^ Printf.sprintf "%S" value
;;

let identifier_option value = quoted_option (Option.map value ~f:Identifier.to_string)

let identifier_list identifiers =
  "[ " ^ String.concat ~sep:"; " (List.map identifiers ~f:quoted) ^ " ]"
;;

let named_descriptor schema name base =
  "Typed_sql_codegen.Db_type.Postgresql.named ~schema:(Typed_sql_codegen.Identifier.of_string_exn "
  ^ quoted schema
  ^ ") ~name:(Typed_sql_codegen.Identifier.of_string_exn "
  ^ quoted name
  ^ ") ("
  ^ base
  ^ ")"
;;

let generate_type_module ~rules ~types typ =
  let open Result.Let_syntax in
  let key = module_key typ in
  let module_name = List.Assoc.find_exn types key ~equal:String.equal in
  match typ with
  | Schema_ir.Enum { schema; name; labels } ->
    if List.is_empty labels then
      Error (Invalid_rules ("enum " ^ key ^ " has no labels"))
    else (
      let _, variants =
        List.fold labels ~init:([], []) ~f:(fun (used, variants) label ->
          let variant, used =
            fresh_name
              ~used
              ~bindings:(fun name -> [ name ])
              (normalized_module_name label)
          in
          used, variants @ [ label, variant ])
      in
      let constructors = List.map variants ~f:snd |> String.concat ~sep:" | " in
      let encode =
        List.map variants ~f:(fun (label, variant) ->
          "    | " ^ variant ^ " -> Stdlib.Result.Ok " ^ Printf.sprintf "%S" label)
        |> String.concat ~sep:"\n"
      in
      let decode =
        List.map variants ~f:(fun (label, variant) ->
          "    | " ^ Printf.sprintf "%S" label ^ " -> Stdlib.Result.Ok " ^ variant)
        |> String.concat ~sep:"\n"
      in
      Ok
        (String.concat
           [ "  module "
           ; module_name
           ; " = struct\n    type t = "
           ; constructors
           ; "\n    let encode = function\n"
           ; encode
           ; "\n    let decode = function\n"
           ; decode
           ; "\n    | _ -> Stdlib.Result.Error \"unknown enum label\"\n"
           ; "    let db_type = Typed_sql_codegen.Db_type.map ~name:"
           ; Printf.sprintf "%S" key
           ; " ~encode ~decode ("
           ; named_descriptor schema name "Typed_sql_codegen.Db_type.text"
           ; ")\n  end\n"
           ]))
  | Schema_ir.Domain { schema; name; base } ->
    let%map base_type, base_descriptor =
      type_source ~rules ~types ~column:None base
      |> Result.map_error ~f:(fun sql_type ->
        Invalid_rules ("unsupported domain base type " ^ sql_type))
    in
    String.concat
      [ "  module "
      ; module_name
      ; " : sig\n    type t\n    val of_base : "
      ; base_type
      ; " -> t\n    val to_base : t -> "
      ; base_type
      ; "\n    val db_type : t Typed_sql_codegen.Db_type.t\n  end = struct\n"
      ; "    type t = Value of "
      ; base_type
      ; "\n    let of_base value = Value value\n"
      ; "    let to_base (Value value) = value\n"
      ; "    let db_type = Typed_sql_codegen.Db_type.map ~name:"
      ; Printf.sprintf "%S" key
      ; " ~encode:(fun value -> Ok (to_base value))"
      ; " ~decode:(fun value -> Ok (of_base value)) ("
      ; named_descriptor schema name base_descriptor
      ; ")\n  end\n"
      ]
  | _ -> Error (Invalid_rules ("not a generated type: " ^ key))
;;

let generate_table ~rules ~types ~module_name (table : Schema_ir.table) =
  if List.is_empty table.columns then
    Error (Empty_table table.name)
  else
    let open Result.Let_syntax in
    let named_columns = allocate_column_names table.columns in
    let%bind columns =
      Result.all
        (List.map named_columns ~f:(fun (column, name) ->
           let column_name =
             (match table.schema with
              | None -> ""
              | Some schema -> Identifier.to_string schema ^ ".")
             ^ Identifier.to_string table.name
             ^ "."
             ^ Identifier.to_string column.name
           in
           type_source ~rules ~types ~column:(Some column_name) column.db_type
           |> Result.map_error ~f:(fun database_type ->
             Unsupported_type { table = table.name; column = column.name; database_type })
           |> Result.map ~f:(fun (ocaml_type, descriptor) ->
             column, name, ocaml_type, descriptor)))
    in
    let table_expression =
      match table.schema with
      | None -> "Typed_sql_codegen.Table.v_exn " ^ quoted table.name
      | Some schema ->
        "Typed_sql_codegen.Table.v_exn ~schema:" ^ quoted schema ^ " " ^ quoted table.name
    in
    let fields =
      List.map columns ~f:(fun (column, name, ocaml_type, _) ->
        let ocaml_type =
          if column.nullable then
            ocaml_type ^ " option"
          else
            ocaml_type
        in
        "    ; " ^ name ^ " : " ^ ocaml_type)
      |> String.concat ~sep:"\n"
    in
    let descriptors =
      List.map columns ~f:(fun (column, name, _, descriptor) ->
        let constructor =
          if column.nullable then
            "Typed_sql_codegen.Column.nullable_v_exn"
          else
            "Typed_sql_codegen.Column.v_exn"
        in
        String.concat
          [ "  let "
          ; name
          ; "_column = "
          ; constructor
          ; " table "
          ; quoted column.name
          ; " ("
          ; descriptor
          ; ")"
          ; "\n  let "
          ; name
          ; " table_ref = Typed_sql_codegen.Expr.column table_ref "
          ; name
          ; "_column"
          ; "\n  let "
          ; name
          ; "_has_default = "
          ; Bool.to_string (Option.is_some column.default)
          ; "\n  let "
          ; name
          ; "_default = "
          ; quoted_option column.default
          ; "\n  let "
          ; name
          ; "_is_generated = "
          ; Bool.to_string column.generated
          ; "\n  let "
          ; name
          ; "_primary_key_position = "
          ; Option.value_map
              column.primary_key_position
              ~default:"None"
              ~f:(fun position -> "Some " ^ Int.to_string position)
          ])
      |> String.concat ~sep:"\n"
    in
    let foreign_keys =
      List.map table.foreign_keys ~f:(fun foreign_key ->
        String.concat
          [ "    ( "
          ; identifier_list foreign_key.columns
          ; ", "
          ; identifier_option foreign_key.referenced_schema
          ; ", "
          ; quoted foreign_key.referenced_table
          ; ", "
          ; identifier_list foreign_key.referenced_columns
          ; " )"
          ])
      |> String.concat ~sep:"\n    ; "
    in
    let unique_constraints =
      List.map table.unique_constraints ~f:(fun constraint_ ->
        "    ( "
        ^ identifier_option constraint_.name
        ^ ", "
        ^ identifier_list constraint_.columns
        ^ " )")
      |> String.concat ~sep:"\n    ; "
    in
    let metadata name contents =
      if String.is_empty contents then
        "  let " ^ name ^ " = []\n"
      else
        "  let " ^ name ^ " =\n    [ " ^ contents ^ "\n    ]\n"
    in
    let bindings =
      List.map columns ~f:(fun (_, name, _, _) ->
        "    and " ^ name ^ " = Typed_sql_codegen.Projection.expr (" ^ name
        ^ " table_ref)")
      |> String.concat ~sep:"\n"
    in
    let record =
      List.map columns ~f:(fun (_, name, _, _) -> name) |> String.concat ~sep:"; "
    in
    let bindings = "    let%map " ^ String.chop_prefix_exn bindings ~prefix:"    and " in
    Ok
      (String.concat
         [ "module "
         ; module_name
         ; " = struct\n"
         ; "  type row\n\n  type t =\n    { "
         ; String.chop_prefix_exn fields ~prefix:"    ; "
         ; "\n    }\n\n"
         ; "  let table : row Typed_sql_codegen.Table.t = "
         ; table_expression
         ; "\n"
         ; descriptors
         ; "\n\n"
         ; metadata "foreign_keys" foreign_keys
         ; metadata "unique_constraints" unique_constraints
         ; "\n"
         ; "  let projection table_ref =\n"
         ; "    let open Typed_sql_codegen.Projection.Let_syntax in\n"
         ; bindings
         ; " in\n    { "
         ; record
         ; " }\n"
         ; "end\n"
         ])
;;

let generate ?(rules = []) schema =
  let open Result.Let_syntax in
  let generated_types = collect_types rules schema in
  let types = type_module_names generated_types in
  let%bind definitions =
    Result.all (List.map generated_types ~f:(generate_type_module ~rules ~types))
  in
  let%map modules =
    Result.all
      (List.map
         (allocate_module_names (Schema_ir.tables schema))
         ~f:(fun (table, module_name) -> generate_table ~rules ~types ~module_name table))
  in
  "open! Base\nmodule Typed_sql_codegen = Typed_sql\nmodule Typed_sql_codegen_ptime = Ptime\n\n"
  ^ "module Typed_sql_generated_types = struct\n"
  ^ String.concat definitions ~sep:"\n"
  ^ "end\n\n"
  ^ String.concat modules ~sep:"\n"
;;
