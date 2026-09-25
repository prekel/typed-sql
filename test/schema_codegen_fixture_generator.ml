open! Base
open Typed_sql

let identifier = Identifier.of_string_exn

let column name db_type =
  Schema_ir.column ~name:(identifier name) ~db_type ~nullable:false ()
;;

let schema =
  Schema_ir.v
    [ Schema_ir.table
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
        ~name:(identifier "user_profile")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ; Schema_ir.table
        ~name:(identifier "USER PROFILE")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ; Schema_ir.table
        ~name:(identifier "table")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ; Schema_ir.table
        ~name:(identifier "typed_sql_codegen")
        ~columns:[ column "id" Schema_ir.Int64 ]
        ()
    ]
;;

let () = Schema_snapshot.to_string schema |> Stdlib.print_string
