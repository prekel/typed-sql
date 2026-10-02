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
WHERE tc.constraint_type = 'PRIMARY KEY'
) AS pk
ON pk.table_schema = c.table_schema
 AND pk.table_name = c.table_name
 AND pk.column_name = c.column_name
WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
AND tables.table_type = 'BASE TABLE'
ORDER BY c.table_schema, c.table_name, c.ordinal_position|}
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
SELECT tc.table_schema,
     tc.table_name,
     tc.constraint_name,
     kcu.ordinal_position,
     kcu.column_name,
     ukcu.table_schema,
     ukcu.table_name,
     ukcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
ON kcu.constraint_catalog = tc.constraint_catalog
 AND kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
ON rc.constraint_catalog = tc.constraint_catalog
 AND rc.constraint_schema = tc.constraint_schema
 AND rc.constraint_name = tc.constraint_name
JOIN information_schema.key_column_usage AS ukcu
ON ukcu.constraint_catalog = rc.unique_constraint_catalog
 AND ukcu.constraint_schema = rc.unique_constraint_schema
 AND ukcu.constraint_name = rc.unique_constraint_name
 AND ukcu.ordinal_position = kcu.position_in_unique_constraint
WHERE tc.constraint_type = 'FOREIGN KEY'
AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position|}
;;

let postgresql_uniques =
  {|
SELECT tc.table_schema,
     tc.table_name,
     tc.constraint_name,
     kcu.ordinal_position,
     kcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
ON kcu.constraint_catalog = tc.constraint_catalog
 AND kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'UNIQUE'
AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position|}
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
  else if contains type_name "TIME" then
    Timestamp
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

let make_schema ~db_type columns foreign_keys uniques =
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
               let%map name = identifier ~context:"column name" name in
               Typed_sql_schema.Schema_ir.column
                 ~name
                 ~db_type:(db_type database_type)
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
        ())
    |> Result.all
  in
  Typed_sql_schema.Schema_ir.v tables
;;
