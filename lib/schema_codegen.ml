open! Base

type error =
  | Empty_table of Identifier.t
  | Unsupported_type of
      { table : Identifier.t
      ; column : Identifier.t
      ; database_type : string
      }

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
  ]
;;

let identifier value =
  let value =
    String.map value ~f:(fun character ->
      if Char.is_alphanum character || Char.equal character '_' then
        character
      else
        '_')
  in
  let value = String.lowercase value in
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
  let reserved = [ "table"; "projection"; "foreign_keys"; "unique_constraints" ] in
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
  loop [] [] tables
;;

let type_source = function
  | Schema_ir.Bool -> Ok ("bool", "Db_type.bool")
  | Schema_ir.Int -> Ok ("int", "Db_type.int")
  | Schema_ir.Int64 -> Ok ("int64", "Db_type.int64")
  | Schema_ir.Float -> Ok ("float", "Db_type.float")
  | Schema_ir.Text -> Ok ("string", "Db_type.text")
  | Schema_ir.Bytes -> Ok ("bytes", "Db_type.bytes")
  | Schema_ir.Date -> Ok ("Date.t", "Db_type.date")
  | Schema_ir.Timestamp -> Ok ("Ptime.t", "Db_type.timestamp")
  | Schema_ir.Uuid -> Ok ("Uuid.t", "Db_type.uuid")
  | Schema_ir.Unsupported name -> Error name
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

let generate_table ~module_name (table : Schema_ir.table) =
  if List.is_empty table.columns then
    Error (Empty_table table.name)
  else
    let open Result.Let_syntax in
    let named_columns = allocate_column_names table.columns in
    let%bind columns =
      Result.all
        (List.map named_columns ~f:(fun (column, name) ->
           type_source column.db_type
           |> Result.map_error ~f:(fun database_type ->
             Unsupported_type { table = table.name; column = column.name; database_type })
           |> Result.map ~f:(fun (ocaml_type, descriptor) ->
             column, name, ocaml_type, descriptor)))
    in
    let table_expression =
      match table.schema with
      | None -> "Table.v_exn " ^ quoted table.name
      | Some schema -> "Table.v_exn ~schema:" ^ quoted schema ^ " " ^ quoted table.name
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
            "Column.nullable_v_exn"
          else
            "Column.v_exn"
        in
        String.concat
          [ "  let "
          ; name
          ; "_column = "
          ; constructor
          ; " table "
          ; quoted column.name
          ; " "
          ; descriptor
          ; "\n  let "
          ; name
          ; " reference = Expr.column reference "
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
        "    and " ^ name ^ " = Projection.expr (" ^ name ^ " reference)")
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
         ; "  let table : row Table.t = "
         ; table_expression
         ; "\n"
         ; descriptors
         ; "\n\n"
         ; metadata "foreign_keys" foreign_keys
         ; metadata "unique_constraints" unique_constraints
         ; "\n"
         ; "  let projection reference =\n"
         ; "    let open Projection.Let_syntax in\n"
         ; bindings
         ; " in\n    { "
         ; record
         ; " }\n"
         ; "end\n"
         ])
;;

let generate schema =
  Result.all
    (List.map
       (allocate_module_names (Schema_ir.tables schema))
       ~f:(fun (table, module_name) -> generate_table ~module_name table))
  |> Result.map ~f:(fun modules ->
    "open! Base\nopen Typed_sql\n\n" ^ String.concat modules ~sep:"\n")
;;
