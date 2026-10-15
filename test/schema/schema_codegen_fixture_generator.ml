open! Base
open Typed_sql_schema

let identifier = Identifier.of_string_exn
let public_schema = identifier "public"

let rec native_info schema name db_type =
  let kind =
    match db_type with
    | Schema_ir.Enum { labels; _ } -> Schema_ir.Native_enum labels
    | Domain { base; name = domain_name; _ } ->
      let base_name =
        match base with
        | Named { name; _ } -> Identifier.to_string name
        | Text ->
          if String.equal (Identifier.to_string domain_name) "username" then
            "varchar"
          else
            "text"
        | _ -> failwith "fixture domain requires an explicit native base"
      in
      Schema_ir.Native_domain
        (native_info (identifier "pg_catalog") (identifier base_name) base)
    | Array Int ->
      Schema_ir.Native_array
        (native_info (identifier "pg_catalog") (identifier "int4") Schema_ir.Int)
    | _ -> Schema_ir.Native_scalar
  in
  { Schema_ir.schema; name; kind }
;;

let column name db_type =
  let pg_catalog = identifier "pg_catalog" in
  let schema, native_name =
    match db_type with
    | Schema_ir.Bool -> pg_catalog, "bool"
    | Int -> pg_catalog, "int4"
    | Int64 -> pg_catalog, "int8"
    | Float -> pg_catalog, "float8"
    | Numeric -> pg_catalog, "numeric"
    | Text -> pg_catalog, "text"
    | Bytes -> pg_catalog, "bytea"
    | Date -> pg_catalog, "date"
    | Timestamp -> pg_catalog, "timestamptz"
    | Timestamp_without_timezone -> pg_catalog, "timestamp"
    | Interval -> pg_catalog, "interval"
    | Json -> pg_catalog, "json"
    | Jsonb -> pg_catalog, "jsonb"
    | Uuid -> pg_catalog, "uuid"
    | Enum { schema; name; _ } | Domain { schema; name; _ } | Named { schema; name } ->
      schema, Identifier.to_string name
    | Array Int -> pg_catalog, "_int4"
    | Array _ | Unsupported _ -> failwith "fixture has an unsupported native type"
  in
  Schema_ir.column
    ~name:(identifier name)
    ~db_type
    ~nullable:false
    ~postgresql_type:(schema, identifier native_name)
    ~postgresql_type_info:(native_info schema (identifier native_name) db_type)
    ~postgresql_attribute_not_null:true
    ~postgresql_type_modifier:(-1)
    ()
;;

let schema =
  let tables =
    [ Schema_ir.table
        ~schema:public_schema
        ~name:(identifier "user-profile")
        ~columns:
          [ column "id" Schema_ir.Int64
          ; column "id-column" Schema_ir.Int
          ; column "display-name" Schema_ir.Text
          ; column "display_name" Schema_ir.Text
          ; column "display.name" Schema_ir.Text
          ; column "table" Schema_ir.Bool
          ; column "published-on" Schema_ir.Date
          ; column "created-at" Schema_ir.Timestamp
          ; column "external-id" Schema_ir.Uuid
          ; column "reference" Schema_ir.Text
          ; column "return" Schema_ir.Text
          ; column "land" Schema_ir.Text
          ; column "_" Schema_ir.Text
          ; column "map" Schema_ir.Text
          ; column "total" Schema_ir.Numeric
          ]
        ()
    ; Schema_ir.table
        ~schema:public_schema
        ~name:(identifier "user_profile")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ; Schema_ir.table
        ~schema:public_schema
        ~name:(identifier "USER PROFILE")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ; Schema_ir.table
        ~schema:public_schema
        ~name:(identifier "table")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ; Schema_ir.table
        ~schema:public_schema
        ~name:(identifier "typed_sql_codegen")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ; Schema_ir.table
        ~schema:public_schema
        ~name:(identifier "advanced")
        ~columns:
          [ column "local_value" Schema_ir.Timestamp_without_timezone
          ; column "float_value" Schema_ir.Timestamp_without_timezone
          ; column "duration" Schema_ir.Interval
          ; column "payload" Schema_ir.Json
          ; column "payload_binary" Schema_ir.Jsonb
          ; column
              "mood"
              (Schema_ir.Enum
                 { schema = identifier "public"
                 ; name = identifier "mood"
                 ; labels = [ "happy"; "sad" ]
                 })
          ; column
              "result_status"
              (Schema_ir.Enum
                 { schema = identifier "public"
                 ; name = identifier "result_status"
                 ; labels = [ "Ok"; "Error" ]
                 })
          ; column
              "username"
              (Schema_ir.Domain
                 { schema = identifier "public"
                 ; name = identifier "username"
                 ; base = Schema_ir.Text
                 })
          ; column
              "host"
              (Schema_ir.Domain
                 { schema = identifier "public"
                 ; name = identifier "host"
                 ; base =
                     Schema_ir.Named
                       { schema = identifier "pg_catalog"; name = identifier "inet" }
                 })
          ; column
              "inet_value"
              (Schema_ir.Named
                 { schema = identifier "pg_catalog"; name = identifier "inet" })
          ; column "small_value" Schema_ir.Int
          ; column "numbers" (Schema_ir.Array Schema_ir.Int)
          ; column
              "rational_value"
              (Schema_ir.Domain
                 { schema = public_schema
                 ; name = identifier "rational"
                 ; base = Schema_ir.Text
                 })
          ; column
              "geometry_value"
              (Schema_ir.Domain
                 { schema = public_schema
                 ; name = identifier "geometry"
                 ; base = Schema_ir.Text
                 })
          ]
        ()
    ]
  in
  Schema_ir.v
    (List.sort tables ~compare:(fun left right ->
       String.compare
         (Identifier.to_string (Schema_ir.table_name left))
         (Identifier.to_string (Schema_ir.table_name right))))
;;

let () = Schema_snapshot.to_string schema |> Stdlib.print_string
