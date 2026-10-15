open! Base

type error = Schema of string

type raw_column =
  string option * string * string * (string * bool * string option * (bool * int option))

type raw_foreign_key =
  string option
  * string
  * string option
  * (int * string * string option * (string * string option))

type raw_unique = string option * string * string option * (int * string)
type raw_attribute = string * string * string * (bool * int * bool option)
type raw_type = int * string * string * (string * int * int * string)

let postgresql_columns =
  {|
SELECT c.table_schema,
     c.table_name,
     c.column_name,
     a.atttypid::text,
     c.is_nullable = 'YES',
     c.column_default,
     c.is_generated = 'ALWAYS' OR c.is_identity = 'YES',
     pk.ordinal_position
FROM information_schema.columns AS c
JOIN information_schema.tables AS tables
ON tables.table_schema = c.table_schema
 AND tables.table_name = c.table_name
JOIN pg_catalog.pg_namespace AS ns ON ns.nspname = c.table_schema
JOIN pg_catalog.pg_class AS rel
ON rel.relnamespace = ns.oid AND rel.relname = c.table_name
JOIN pg_catalog.pg_attribute AS a
ON a.attrelid = rel.oid AND a.attname = c.column_name
LEFT JOIN (
SELECT kcu.table_schema,
       kcu.table_name,
       kcu.column_name,
       kcu.ordinal_position
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON kcu.constraint_catalog = tc.constraint_catalog
 AND kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
 AND kcu.table_catalog = tc.table_catalog
 AND kcu.table_schema = tc.table_schema
 AND kcu.table_name = tc.table_name
WHERE tc.constraint_type = 'PRIMARY KEY'
) AS pk
ON pk.table_schema = c.table_schema
 AND pk.table_name = c.table_name
 AND pk.column_name = c.column_name
WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
AND tables.table_type = 'BASE TABLE'
ORDER BY c.table_schema, c.table_name, c.ordinal_position|}
;;

let postgresql_attributes =
  {|SELECT ns.nspname, rel.relname, a.attname, a.attnotnull, a.atttypmod,
 (SELECT con.condeferrable FROM pg_catalog.pg_constraint AS con
  WHERE con.conrelid = rel.oid AND con.contype = 'p')
FROM pg_catalog.pg_attribute AS a
JOIN pg_catalog.pg_class AS rel ON rel.oid = a.attrelid
JOIN pg_catalog.pg_namespace AS ns ON ns.oid = rel.relnamespace
WHERE rel.relkind IN ('r', 'p') AND a.attnum > 0 AND NOT a.attisdropped
AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY ns.nspname, rel.relname, a.attnum|}
;;

let postgresql_types =
  {|
SELECT t.oid::integer,
     n.nspname,
     t.typname,
     t.typtype::text,
     t.typbasetype::integer,
     t.typelem::integer,
     COALESCE(
       (SELECT json_agg(e.enumlabel ORDER BY e.enumsortorder)::text
        FROM pg_catalog.pg_enum AS e WHERE e.enumtypid = t.oid),
       '[]')
FROM pg_catalog.pg_type AS t
JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace|}
;;

let postgresql_foreign_keys =
  {|
SELECT ns.nspname,
     rel.relname,
     con.conname,
     key.ordinality::integer,
     col.attname,
     target_ns.nspname,
     target.relname,
     target_col.attname
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS rel ON rel.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS ns ON ns.oid = rel.relnamespace
JOIN pg_catalog.pg_class AS target ON target.oid = con.confrelid
JOIN pg_catalog.pg_namespace AS target_ns ON target_ns.oid = target.relnamespace
JOIN LATERAL unnest(con.conkey, con.confkey) WITH ORDINALITY
  AS key(attnum, target_attnum, ordinality) ON true
JOIN pg_catalog.pg_attribute AS col
ON col.attrelid = con.conrelid AND col.attnum = key.attnum
JOIN pg_catalog.pg_attribute AS target_col
ON target_col.attrelid = con.confrelid AND target_col.attnum = key.target_attnum
WHERE con.contype = 'f'
AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
AND rel.relkind IN ('r', 'p')
ORDER BY ns.nspname, rel.relname, con.conname, key.ordinality|}
;;

let postgresql_uniques =
  {|
SELECT ns.nspname,
     rel.relname,
     idx.relname,
     key.ordinality::integer,
     col.attname
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS rel ON rel.oid = i.indrelid
JOIN pg_catalog.pg_namespace AS ns ON ns.oid = rel.relnamespace
JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS key(attnum, ordinality)
  ON key.ordinality <= i.indnkeyatts
JOIN pg_catalog.pg_attribute AS col
  ON col.attrelid = i.indrelid AND col.attnum = key.attnum
WHERE i.indisunique AND NOT i.indisprimary AND i.indisvalid
AND i.indpred IS NULL AND i.indexprs IS NULL
AND rel.relkind IN ('r', 'p')
AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY ns.nspname, rel.relname, idx.relname, key.ordinality|}
;;

let identifier ~context value =
  Typed_sql.Identifier.of_string value
  |> Result.map_error ~f:(fun error ->
    Schema (context ^ ": " ^ Typed_sql.Identifier.error_to_string error))
;;

let optional_identifier ~context = function
  | None -> Ok None
  | Some value -> Result.map (identifier ~context value) ~f:Option.some
;;

let contains type_name fragment =
  String.is_substring (String.uppercase type_name) ~substring:fragment
;;

let sqlite_db_type type_name =
  let open Typed_sql_schema.Schema_ir in
  if String.is_empty type_name || contains type_name "BLOB" then
    Bytes
  else if contains type_name "BOOL" then
    Bool
  else if contains type_name "TIMESTAMP" || contains type_name "DATETIME" then
    Timestamp
  else if contains type_name "TIME" then
    Unsupported type_name
  else if contains type_name "DATE" then
    Date
  else if contains type_name "UUID" then
    Uuid
  else if contains type_name "INT" then
    Int64
  else if
    contains type_name "CHAR" || contains type_name "CLOB" || contains type_name "TEXT"
  then
    Text
  else if
    contains type_name "REAL" || contains type_name "FLOA" || contains type_name "DOUB"
  then
    Float
  else
    Unsupported type_name
;;

let postgresql_db_type type_name =
  let open Typed_sql_schema.Schema_ir in
  match String.lowercase type_name with
  | "bool" -> Bool
  | "int2" | "int4" -> Int
  | "int8" -> Int64
  | "float4" | "float8" -> Float
  | "numeric" | "decimal" -> Numeric
  | "text" | "bpchar" | "varchar" -> Text
  | "bytea" -> Bytes
  | "date" -> Date
  | "timestamptz" -> Timestamp
  | "timestamp" -> Timestamp_without_timezone
  | "interval" -> Interval
  | "json" -> Json
  | "jsonb" -> Jsonb
  | "uuid" -> Uuid
  | unsupported -> Unsupported unsupported
;;

let postgresql_type_mapper rows =
  let rec convert seen oid =
    let open Typed_sql_schema.Schema_ir in
    if List.mem seen oid ~equal:Int.equal then
      Unsupported ("recursive type oid " ^ Int.to_string oid)
    else (
      match
        List.find rows ~f:(fun (row_oid, _, _, _) -> Int.equal oid row_oid)
      with
      | None -> Unsupported ("unknown type oid " ^ Int.to_string oid)
      | Some (_, schema, name, (kind, base_oid, element_oid, labels)) ->
        let schema = Typed_sql.Identifier.of_string_exn schema in
        let name_id = Typed_sql.Identifier.of_string_exn name in
        let next = oid :: seen in
        (match kind with
         | "d" -> Domain { schema; name = name_id; base = convert next base_oid }
         | "e" ->
           let labels =
             match Yojson.Safe.from_string labels with
             | `List values ->
               List.filter_map values ~f:(function
                 | `String value -> Some value
                 | _ -> None)
             | _ -> []
           in
           Enum { schema; name = name_id; labels }
         | _ when String.is_prefix name ~prefix:"_" && Int.(element_oid <> 0) ->
           Array (convert next element_oid)
         | _ when String.equal (Typed_sql.Identifier.to_string schema) "pg_catalog" ->
           (match postgresql_db_type name with
            | Unsupported _ -> Named { schema; name = name_id }
            | known -> known)
         | _ -> Named { schema; name = name_id }))
  in
  fun oid ->
    match Int.of_string_opt oid with
    | Some oid -> convert [] oid
    | None -> Typed_sql_schema.Schema_ir.Unsupported ("invalid type oid " ^ oid)
;;

let same_key (left_schema, left_table, left_name) (right_schema, right_table, right_name) =
  Option.equal String.equal left_schema right_schema
  && String.equal left_table right_table
  && Option.equal String.equal left_name right_name
;;

let group_adjacent rows ~key =
  List.group rows ~break:(fun left right -> not (same_key (key left) (key right)))
;;

let primary_key_columns columns ~schema ~table =
  List.filter_map
    columns
    ~f:(fun (column_schema, column_table, column, (_, _, _, (_, pk))) ->
      if Option.equal String.equal schema column_schema && String.equal table column_table
      then
        Option.map pk ~f:(fun position -> position, column)
      else
        None)
  |> List.sort ~compare:(fun (left, _) (right, _) -> Int.compare left right)
  |> List.map ~f:snd
;;

let make_foreign_keys ~primary_key_columns rows =
  group_adjacent rows ~key:(fun (schema, table, name, _) -> schema, table, name)
  |> List.map ~f:(fun group ->
    let _, _, _, (_, _, referenced_schema_name, (referenced_table_name, _)) =
      List.hd_exn group
    in
    let open Result.Let_syntax in
    let%bind columns =
      Result.all
        (List.map group ~f:(fun (_, _, _, (_, column, _, _)) ->
           identifier ~context:"foreign-key column" column))
    in
    let%bind referenced_schema =
      optional_identifier ~context:"referenced schema" referenced_schema_name
    in
    let%bind referenced_table =
      identifier ~context:"referenced table" referenced_table_name
    in
    let referenced_columns =
      List.map group ~f:(fun (_, _, _, (_, _, _, (_, column))) -> column)
    in
    let%bind referenced_columns =
      match List.for_all referenced_columns ~f:Option.is_some with
      | true ->
        Result.all
          (List.map referenced_columns ~f:(fun column ->
             identifier ~context:"referenced column" (Option.value_exn column)))
      | false when List.for_all referenced_columns ~f:Option.is_none ->
        (match
           primary_key_columns ~schema:referenced_schema_name ~table:referenced_table_name
         with
         | [] ->
           Error
             (Schema
                ("referenced table " ^ referenced_table_name
               ^ " has no primary key for an implicit foreign key target"))
         | columns ->
           Result.all
             (List.map columns ~f:(identifier ~context:"referenced primary-key column")))
      | false ->
        Error
          (Schema
             ("foreign key to " ^ referenced_table_name
            ^ " mixes explicit and implicit referenced columns"))
    in
    Ok
      (Typed_sql_schema.Schema_ir.foreign_key
         ~columns
         ?referenced_schema
         ~referenced_table
         ~referenced_columns
         ()))
  |> Result.all
;;

let make_uniques rows =
  group_adjacent rows ~key:(fun (schema, table, name, _) -> schema, table, name)
  |> List.map ~f:(fun group ->
    let _, _, name, _ = List.hd_exn group in
    let open Result.Let_syntax in
    let%bind name = optional_identifier ~context:"unique constraint" name in
    let%map columns =
      Result.all
        (List.map group ~f:(fun (_, _, _, (_, column)) ->
           identifier ~context:"unique column" column))
    in
    Typed_sql_schema.Schema_ir.unique_constraint ?name columns)
  |> Result.all
;;

let belongs_to_table ~schema ~table (row_schema, row_table, _, _) =
  Option.equal String.equal schema row_schema && String.equal table row_table
;;

let postgresql_column_type rows oid =
  Option.bind (Int.of_string_opt oid) ~f:(fun oid ->
    List.find rows ~f:(fun (row_oid, _, _, _) -> Int.equal oid row_oid)
    |> Option.map ~f:(fun (_, schema, name, _) ->
      Typed_sql.Identifier.of_string_exn schema, Typed_sql.Identifier.of_string_exn name))
;;

let postgresql_type_info rows oid =
  let open Result.Let_syntax in
  let rec resolve seen oid =
    if List.mem seen oid ~equal:Int.equal then
      Error (Schema "cyclic native type metadata")
    else (
      match
        List.find rows ~f:(fun (id, _, _, _) -> Int.equal id oid)
      with
      | None -> Error (Schema ("missing native type OID " ^ Int.to_string oid))
      | Some (_, schema, name, (kind, base, element, labels)) ->
        let%bind schema = identifier ~context:"native type schema" schema in
        let%bind name = identifier ~context:"native type name" name in
        let next = oid :: seen in
        let%map kind =
          match kind with
          | "d" ->
            let%map base = resolve next base in
            Typed_sql_schema.Schema_ir.Native_domain base
          | "e" ->
            let%bind json =
              Result.try_with (fun () -> Yojson.Safe.from_string labels)
              |> Result.map_error ~f:(fun _ -> Schema "invalid enum labels JSON")
            in
            (match json with
             | `List labels ->
               let%map labels =
                 List.map labels ~f:(function
                   | `String value -> Ok value
                   | _ -> Error (Schema "invalid enum label"))
                 |> Result.all
               in
               Typed_sql_schema.Schema_ir.Native_enum labels
             | _ -> Error (Schema "enum labels must be an array"))
          | "b"
            when String.is_prefix (Typed_sql.Identifier.to_string name) ~prefix:"_"
                 && Int.(element <> 0) ->
            let%map element = resolve next element in
            Typed_sql_schema.Schema_ir.Native_array element
          | "b" when String.equal (Typed_sql.Identifier.to_string schema) "pg_catalog" ->
            Ok Typed_sql_schema.Schema_ir.Native_scalar
          | _ -> Ok Typed_sql_schema.Schema_ir.Native_opaque
        in
        { Typed_sql_schema.Schema_ir.schema; name; kind })
  in
  match Int.of_string_opt oid with
  | None -> Error (Schema "invalid native type OID")
  | Some oid ->
    let%map info = resolve [] oid in
    Some info
;;

let postgresql_attribute_not_null rows schema table column =
  List.find_map
    rows
    ~f:(fun (actual_schema, actual_table, actual_column, (not_null, _, _)) ->
      if
        Option.value_map schema ~default:false ~f:(String.equal actual_schema)
        && String.equal table actual_table
        && String.equal column actual_column
      then
        Some not_null
      else
        None)
;;

let postgresql_type_modifier rows schema table column =
  List.find_map
    rows
    ~f:(fun (actual_schema, actual_table, actual_column, (_, modifier, _)) ->
      if
        Option.value_map schema ~default:false ~f:(String.equal actual_schema)
        && String.equal table actual_table
        && String.equal column actual_column
      then
        Some modifier
      else
        None)
;;

let postgresql_primary_key_deferrable rows schema table =
  List.find_map rows ~f:(fun (actual_schema, actual_table, _, (_, _, flag)) ->
    if
      Option.value_map schema ~default:false ~f:(String.equal actual_schema)
      && String.equal table actual_table
    then
      flag
    else
      None)
;;

let make_schema
      ?(postgresql_type = fun _ -> None)
      ?(postgresql_type_info = fun _ -> Ok None)
      ?(postgresql_attribute_not_null = fun _ _ _ -> None)
      ?(postgresql_type_modifier = fun _ _ _ -> None)
      ?(postgresql_primary_key_deferrable = fun _ _ -> None)
      ~db_type
      columns
      foreign_keys
      uniques
  =
  let open Result.Let_syntax in
  let primary_keys = primary_key_columns columns in
  let column_groups =
    List.group
      columns
      ~break:(fun (left_schema, left_table, _, _) (right_schema, right_table, _, _) ->
        not
          (Option.equal String.equal left_schema right_schema
           && String.equal left_table right_table))
  in
  let%map tables =
    List.map column_groups ~f:(fun group ->
      let schema, table, _, _ = List.hd_exn group in
      let%bind schema = optional_identifier ~context:"table schema" schema in
      let%bind name = identifier ~context:"table name" table in
      let%bind columns =
        Result.all
          (List.map
             group
             ~f:
               (fun
                 ( _
                 , _
                 , name
                 , (database_type, nullable, default, (generated, primary_key_position))
                 )
               ->
               let attribute_not_null =
                 postgresql_attribute_not_null
                   (Option.map schema ~f:Typed_sql.Identifier.to_string)
                   table
                   name
               in
               let%bind native_info = postgresql_type_info database_type in
               let%map name = identifier ~context:"column name" name in
               Typed_sql_schema.Schema_ir.column
                 ~name
                 ~db_type:(db_type database_type)
                 ?postgresql_type:(postgresql_type database_type)
                 ?postgresql_type_info:native_info
                 ?postgresql_attribute_not_null:attribute_not_null
                 ?postgresql_type_modifier:
                   (postgresql_type_modifier
                      (Option.map schema ~f:Typed_sql.Identifier.to_string)
                      table
                      (Typed_sql.Identifier.to_string name))
                 ~nullable
                 ?default
                 ~generated
                 ?primary_key_position
                 ()))
      in
      let raw_foreign_keys =
        List.filter
          foreign_keys
          ~f:
            (belongs_to_table
               ~schema:(Option.map schema ~f:Typed_sql.Identifier.to_string)
               ~table)
      in
      let raw_uniques =
        List.filter
          uniques
          ~f:
            (belongs_to_table
               ~schema:(Option.map schema ~f:Typed_sql.Identifier.to_string)
               ~table)
      in
      let%bind foreign_keys =
        make_foreign_keys ~primary_key_columns:primary_keys raw_foreign_keys
      in
      let%map unique_constraints = make_uniques raw_uniques in
      Typed_sql_schema.Schema_ir.table
        ?schema
        ~name
        ~columns
        ~foreign_keys
        ~unique_constraints
        ?postgresql_primary_key_deferrable:
          (postgresql_primary_key_deferrable
             (Option.map schema ~f:Typed_sql.Identifier.to_string)
             table)
        ())
    |> Result.all
  in
  Typed_sql_schema.Schema_ir.v tables
;;
