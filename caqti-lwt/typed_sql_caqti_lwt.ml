open! Base
module T = Caqti.Template

type constraint_kind =
  | Unique
  | Foreign_key
  | Not_null
  | Check
  | Restrict
  | Exclusion
  | Other

type error =
  | Compile of Typed_sql.Compile_error.t
  | Unsupported_dialect of string
  | Codec of string
  | Schema of string
  | Constraint_violation of
      { kind : constraint_kind
      ; message : string
      }
  | Caqti of Caqti.Error.t

let error_to_string = function
  | Compile error -> Typed_sql.Compile_error.to_string error
  | Unsupported_dialect dialect -> "unsupported Caqti dialect: " ^ dialect
  | Codec message -> "codec failed: " ^ message
  | Schema message -> "schema introspection failed: " ^ message
  | Constraint_violation { kind; message } ->
    let kind =
      match kind with
      | Unique -> "unique"
      | Foreign_key -> "foreign key"
      | Not_null -> "not null"
      | Check -> "check"
      | Restrict -> "restrict"
      | Exclusion -> "exclusion"
      | Other -> "integrity"
    in
    kind ^ " constraint violation: " ^ message
  | Caqti error -> Caqti.Error.show error
;;

let pp_error formatter error =
  Stdlib.Format.pp_print_string formatter (error_to_string error)
;;

let dialect_of_caqti = function
  | T.Dialect.Pgsql _ -> Ok Typed_sql.Dialect.Postgresql
  | T.Dialect.Sqlite _ -> Ok Typed_sql.Dialect.Sqlite
  | T.Dialect.Mysql _ -> Error (Unsupported_dialect "mysql")
  | T.Dialect.Unknown _ -> Error (Unsupported_dialect "unknown")
  | _ -> Error (Unsupported_dialect "unregistered")
;;

type 'a caqti_codec =
  | Caqti_codec :
      { row_type : 'repr T.Row_type.t
      ; encode : 'a -> ('repr, string) Result.t
      ; decode : 'repr -> ('a, string) Result.t
      }
      -> 'a caqti_codec

let rec caqti_codec : type a. a Typed_sql_backend.Db_type.t -> a caqti_codec =
  fun db_type ->
  match Typed_sql_backend.Db_type.view db_type with
  | Bool ->
    Caqti_codec
      { row_type = T.Row_type.bool; encode = Result.return; decode = Result.return }
  | Int ->
    Caqti_codec
      { row_type = T.Row_type.int; encode = Result.return; decode = Result.return }
  | Int64 ->
    Caqti_codec
      { row_type = T.Row_type.int64; encode = Result.return; decode = Result.return }
  | Float ->
    Caqti_codec
      { row_type = T.Row_type.float; encode = Result.return; decode = Result.return }
  | Text ->
    Caqti_codec
      { row_type = T.Row_type.string; encode = Result.return; decode = Result.return }
  | Bytes ->
    Caqti_codec
      { row_type = T.Row_type.octets
      ; encode = (fun value -> Ok (Stdlib.Bytes.to_string value))
      ; decode = (fun value -> Ok (Stdlib.Bytes.of_string value))
      }
  | Timestamp ->
    Caqti_codec
      { row_type = T.Row_type.ptime; encode = Result.return; decode = Result.return }
  | Option db_type ->
    (match caqti_codec db_type with
     | Caqti_codec codec ->
       Caqti_codec
         { row_type = T.Row_type.option codec.row_type
         ; encode =
             (function
               | None -> Ok None
               | Some value -> Result.map (codec.encode value) ~f:Option.some)
         ; decode =
             (function
               | None -> Ok None
               | Some value -> Result.map (codec.decode value) ~f:Option.some)
         })
  | Map { repr; encode; decode; _ } ->
    (match caqti_codec repr with
     | Caqti_codec repr_codec ->
       Caqti_codec
         { row_type = repr_codec.row_type
         ; encode =
             (fun value ->
               let open Result.Let_syntax in
               let%bind repr = encode value in
               repr_codec.encode repr)
         ; decode =
             (fun raw ->
               let open Result.Let_syntax in
               let%bind repr = repr_codec.decode raw in
               decode repr)
         })
;;

type packed_parameters =
  | Parameters :
      { row_type : 'parameters T.Row_type.t
      ; value : 'parameters
      }
      -> packed_parameters

let pack_parameters parameters =
  List.fold
    parameters
    ~init:(Ok (Parameters { row_type = T.Row_type.unit; value = () }))
    ~f:(fun result (Typed_sql_backend.Db_type.Value (db_type, value)) ->
      let open Result.Let_syntax in
      let%bind (Parameters packed) = result in
      let (Caqti_codec codec) = caqti_codec db_type in
      let%map value =
        codec.encode value |> Result.map_error ~f:(fun message -> Codec message)
      in
      Parameters
        { row_type = T.Row_type.t2 packed.row_type codec.row_type
        ; value = packed.value, value
        })
;;

type 'result projection_row =
  | Projection_row :
      { row_type : 'raw T.Row_type.t
      ; decode : 'raw -> ('result, error) Result.t
      }
      -> 'result projection_row

module Projection_decoder = Typed_sql_backend.Projection.Make (struct
    type 'a t = 'a projection_row

    include Applicative.Make_using_map2 (struct
        type nonrec 'a t = 'a t

        let return value =
          Projection_row { row_type = T.Row_type.unit; decode = (fun () -> Ok value) }
        ;;

        let map (Projection_row row) ~f =
          Projection_row
            { row_type = row.row_type
            ; decode = (fun raw -> Result.map (row.decode raw) ~f)
            }
        ;;

        let map2 (Projection_row left) (Projection_row right) ~f =
          Projection_row
            { row_type = T.Row_type.t2 left.row_type right.row_type
            ; decode =
                (fun (a, b) ->
                  let open Result.Let_syntax in
                  let%bind a = left.decode a in
                  let%map b = right.decode b in
                  f a b)
            }
        ;;

        let map = `Custom map
      end)

    let field db_type =
      match caqti_codec db_type with
      | Caqti_codec codec ->
        Projection_row
          { row_type = codec.row_type
          ; decode =
              (fun raw ->
                codec.decode raw |> Result.map_error ~f:(fun message -> Codec message))
          }
    ;;
  end)

let projection_row = Projection_decoder.run

let caqti_query template =
  Typed_sql_backend.Template.map template ~text:T.Query.lit ~param:T.Query.param
  |> T.Query.concat
;;

let classify_caqti_error (error : Caqti.Error.t) =
  let constraint_kind = function
    | `Unique_violation -> Some Unique
    | `Foreign_key_violation -> Some Foreign_key
    | `Not_null_violation -> Some Not_null
    | `Check_violation -> Some Check
    | `Restrict_violation -> Some Restrict
    | `Exclusion_violation -> Some Exclusion
    | `Integrity_constraint_violation__don't_match -> Some Other
    | _ -> None
  in
  let cause =
    match error with
    | (`Request_failed _ | `Response_failed _) as error -> Some (Caqti.Error.cause error)
    | _ -> None
  in
  match Option.bind cause ~f:constraint_kind with
  | Some kind -> Constraint_violation { kind; message = Caqti.Error.show error }
  | None -> Caqti error
;;

let map_caqti_error result =
  Result.map_error result ~f:(fun error -> classify_caqti_error (error :> Caqti.Error.t))
;;

let compile dialect query =
  let open Result.Let_syntax in
  let%bind dialect = dialect_of_caqti dialect in
  Typed_sql.Compiler.compile ~dialect query
  |> Result.map_error ~f:(fun error -> Compile error)
;;

let compile_command dialect command =
  let open Result.Let_syntax in
  let%bind dialect = dialect_of_caqti dialect in
  Typed_sql.Compiler.compile_command ~dialect command
  |> Result.map_error ~f:(fun error -> Compile error)
;;

let fetch ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       (match projection_row (Typed_sql_backend.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->* row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql_backend.Compiled_query.template compiled))
          in
          Connection.collect_list request parameters.value
          |> Lwt.map (fun result ->
            let open Result.Let_syntax in
            let%bind rows = map_caqti_error result in
            Result.all (List.map rows ~f:row.decode))))
;;

let fetch_one ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       (match projection_row (Typed_sql_backend.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->! row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql_backend.Compiled_query.template compiled))
          in
          Connection.find request parameters.value
          |> Lwt.map (fun result ->
            let open Result.Let_syntax in
            let%bind raw = map_caqti_error result in
            row.decode raw)))
;;

let fetch_opt ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       (match projection_row (Typed_sql_backend.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->? row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql_backend.Compiled_query.template compiled))
          in
          Connection.find_opt request parameters.value
          |> Lwt.map (fun result ->
            let open Result.Let_syntax in
            let%bind raw = map_caqti_error result in
            match raw with
            | None -> Ok None
            | Some raw -> Result.map (row.decode raw) ~f:Option.some)))
;;

let execute ~conn command =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile_command Connection.dialect command with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_command.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       let request_type =
         T.Request_type.Infix.(parameters.row_type -->. T.Row_type.unit)
       in
       let request =
         T.Request.create T.Request.Dynamic request_type (fun _ ->
           caqti_query (Typed_sql_backend.Compiled_command.template compiled))
       in
       Connection.exec_with_affected_count request parameters.value
       |> Lwt.map (function
         | Ok count -> Ok (Typed_sql.Affected_rows.Known count)
         | Error `Unsupported -> Ok Typed_sql.Affected_rows.Unknown
         | Error (#Caqti.Error.t as error) ->
           Error (classify_caqti_error (error :> Caqti.Error.t))))
;;

let transaction ~conn ~f =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let map_transaction_error result = Lwt.map map_caqti_error result in
  let open Lwt.Syntax in
  let* started = map_transaction_error (Connection.start ()) in
  match started with
  | Error error -> Lwt.return (Error error)
  | Ok () ->
    Lwt.catch
      (fun () ->
         let* result = f conn in
         match result with
         | Ok value ->
           let* committed = map_transaction_error (Connection.commit ()) in
           Lwt.return (Result.map committed ~f:(fun () -> value))
         | Error error ->
           let* rolled_back = map_transaction_error (Connection.rollback ()) in
           (match rolled_back with
            | Ok () -> Lwt.return (Error error)
            | Error rollback_error -> Lwt.return (Error rollback_error)))
      (fun exn ->
         let* _ = Connection.rollback () in
         Lwt.fail exn)
;;

module Schema = struct
  type raw_column =
    string option
    * string
    * string
    * (string * bool * string option * (bool * int option))

  type raw_foreign_key =
    string option
    * string
    * string option
    * (int * string * string option * (string * string))

  type raw_unique = string option * string * string option * (int * string)

  let column_row_type : raw_column T.Row_type.t =
    T.Row_type.t4
      (T.Row_type.option T.Row_type.string)
      T.Row_type.string
      T.Row_type.string
      (T.Row_type.t4
         T.Row_type.string
         T.Row_type.bool
         (T.Row_type.option T.Row_type.string)
         (T.Row_type.t2 T.Row_type.bool (T.Row_type.option T.Row_type.int)))
  ;;

  let foreign_key_row_type : raw_foreign_key T.Row_type.t =
    T.Row_type.t4
      (T.Row_type.option T.Row_type.string)
      T.Row_type.string
      (T.Row_type.option T.Row_type.string)
      (T.Row_type.t4
         T.Row_type.int
         T.Row_type.string
         (T.Row_type.option T.Row_type.string)
         (T.Row_type.t2 T.Row_type.string T.Row_type.string))
  ;;

  let unique_row_type : raw_unique T.Row_type.t =
    T.Row_type.t4
      (T.Row_type.option T.Row_type.string)
      T.Row_type.string
      (T.Row_type.option T.Row_type.string)
      (T.Row_type.t2 T.Row_type.int T.Row_type.string)
  ;;

  let request row_type sql =
    T.Request.create
      T.Request.Direct
      T.Request_type.Infix.(T.Row_type.unit -->* row_type)
      (fun _ -> T.Query.parse sql)
  ;;

  let sqlite_columns =
    {|
SELECT NULL,
       m.name,
       x.name,
       x.type,
       x."notnull" = 0,
       x.dflt_value,
       x.hidden IN (2, 3),
       CASE WHEN x.pk = 0 THEN NULL ELSE x.pk END
FROM sqlite_schema AS m
JOIN pragma_table_xinfo(m.name) AS x
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, x.cid|}
  ;;

  let sqlite_foreign_keys =
    {|
SELECT NULL,
       m.name,
       CAST(f.id AS TEXT),
       f.seq,
       f."from",
       NULL,
       f."table",
       f."to"
FROM sqlite_schema AS m
JOIN pragma_foreign_key_list(m.name) AS f
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, f.id, f.seq|}
  ;;

  let sqlite_uniques =
    {|
SELECT NULL,
       m.name,
       il.name,
       ii.seqno,
       ii.name
FROM sqlite_schema AS m
JOIN pragma_index_list(m.name) AS il
JOIN pragma_index_info(il.name) AS ii
WHERE m.type = 'table'
  AND m.name NOT LIKE 'sqlite_%'
  AND il."unique" = 1
  AND il.origin <> 'pk'
ORDER BY m.name, il.name, ii.seqno|}
  ;;

  let postgresql_columns =
    {|
SELECT c.table_schema,
       c.table_name,
       c.column_name,
       CASE
         WHEN c.data_type = 'USER-DEFINED' THEN c.udt_schema || '.' || c.udt_name
         WHEN c.data_type = 'ARRAY' THEN c.udt_schema || '.' || c.udt_name || '[]'
         ELSE c.data_type
       END,
       c.is_nullable = 'YES',
       c.column_default,
       c.is_generated = 'ALWAYS' OR c.is_identity = 'YES',
       pk.ordinal_position
FROM information_schema.columns AS c
JOIN information_schema.tables AS tables
  ON tables.table_schema = c.table_schema
 AND tables.table_name = c.table_name
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
    let open Typed_sql.Schema_ir in
    if String.is_empty type_name || contains type_name "BLOB" then
      Bytes
    else if contains type_name "BOOL" then
      Bool
    else if contains type_name "DATE" || contains type_name "TIME" then
      Timestamp
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
    let open Typed_sql.Schema_ir in
    match String.lowercase type_name with
    | "boolean" -> Bool
    | "smallint" | "integer" -> Int
    | "bigint" -> Int64
    | "real" | "double precision" -> Float
    | "text" | "character" | "character varying" -> Text
    | "bytea" -> Bytes
    | "timestamp with time zone" -> Timestamp
    | unsupported -> Unsupported unsupported
  ;;

  let same_key (left_schema, left_table, left_name) (right_schema, right_table, right_name)
    =
    Option.equal String.equal left_schema right_schema
    && String.equal left_table right_table
    && Option.equal String.equal left_name right_name
  ;;

  let group_adjacent rows ~key =
    List.group rows ~break:(fun left right -> not (same_key (key left) (key right)))
  ;;

  let make_foreign_keys rows =
    group_adjacent rows ~key:(fun (schema, table, name, _) -> schema, table, name)
    |> List.map ~f:(fun group ->
      let _, _, _, (_, _, referenced_schema, (referenced_table, _)) = List.hd_exn group in
      let open Result.Let_syntax in
      let%bind columns =
        Result.all
          (List.map group ~f:(fun (_, _, _, (_, column, _, _)) ->
             identifier ~context:"foreign-key column" column))
      in
      let%bind referenced_schema =
        optional_identifier ~context:"referenced schema" referenced_schema
      in
      let%bind referenced_table =
        identifier ~context:"referenced table" referenced_table
      in
      let%map referenced_columns =
        Result.all
          (List.map group ~f:(fun (_, _, _, (_, _, _, (_, column))) ->
             identifier ~context:"referenced column" column))
      in
      Typed_sql.Schema_ir.foreign_key
        ~columns
        ?referenced_schema
        ~referenced_table
        ~referenced_columns
        ())
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
      Typed_sql.Schema_ir.unique_constraint ?name columns)
    |> Result.all
  ;;

  let belongs_to_table ~schema ~table (row_schema, row_table, _, _) =
    Option.equal String.equal schema row_schema && String.equal table row_table
  ;;

  let make_schema ~db_type columns foreign_keys uniques =
    let open Result.Let_syntax in
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
                 Typed_sql.Schema_ir.column
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
        let%bind foreign_keys = make_foreign_keys raw_foreign_keys in
        let%map unique_constraints = make_uniques raw_uniques in
        Typed_sql.Schema_ir.table
          ?schema
          ~name
          ~columns
          ~foreign_keys
          ~unique_constraints
          ())
      |> Result.all
    in
    Typed_sql.Schema_ir.v tables
  ;;

  let introspect_with ~conn ~columns_sql ~foreign_keys_sql ~uniques_sql ~db_type =
    let module Connection = (val conn : Caqti_lwt.CONNECTION) in
    let open Lwt.Syntax in
    let* columns = Connection.collect_list (request column_row_type columns_sql) () in
    match map_caqti_error columns with
    | Error error -> Lwt.return (Error error)
    | Ok columns ->
      let* foreign_keys =
        Connection.collect_list (request foreign_key_row_type foreign_keys_sql) ()
      in
      (match map_caqti_error foreign_keys with
       | Error error -> Lwt.return (Error error)
       | Ok foreign_keys ->
         let* uniques =
           Connection.collect_list (request unique_row_type uniques_sql) ()
         in
         Lwt.return
           (let open Result.Let_syntax in
            let%bind uniques = map_caqti_error uniques in
            make_schema ~db_type columns foreign_keys uniques))
  ;;

  let introspect ~conn =
    let module Connection = (val conn : Caqti_lwt.CONNECTION) in
    match Connection.dialect with
    | T.Dialect.Sqlite _ ->
      introspect_with
        ~conn
        ~columns_sql:sqlite_columns
        ~foreign_keys_sql:sqlite_foreign_keys
        ~uniques_sql:sqlite_uniques
        ~db_type:sqlite_db_type
    | T.Dialect.Pgsql _ ->
      introspect_with
        ~conn
        ~columns_sql:postgresql_columns
        ~foreign_keys_sql:postgresql_foreign_keys
        ~uniques_sql:postgresql_uniques
        ~db_type:postgresql_db_type
    | T.Dialect.Mysql _ -> Lwt.return (Error (Unsupported_dialect "mysql"))
    | T.Dialect.Unknown _ -> Lwt.return (Error (Unsupported_dialect "unknown"))
    | _ -> Lwt.return (Error (Unsupported_dialect "unregistered"))
  ;;
end
