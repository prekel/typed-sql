open! Base
open Typed_sql

let identifier = Identifier.of_string_exn
let public_schema = identifier "public"

let column name db_type =
  Schema_ir.column ~name:(identifier name) ~db_type ~nullable:false ()
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
