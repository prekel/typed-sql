open! Base
open Typed_sql_schema

let%test_unit "schema IR preserves metadata and generates public descriptors" =
  let identifier = Identifier.of_string_exn in
  let columns =
    [ Schema_ir.column
        ~name:(identifier "id")
        ~db_type:Int64
        ~nullable:false
        ~primary_key_position:1
        ()
    ; Schema_ir.column
        ~name:(identifier "display-name")
        ~db_type:Text
        ~nullable:true
        ~default:"'anonymous'"
        ()
    ; Schema_ir.column
        ~name:(identifier "created_at")
        ~db_type:Timestamp
        ~nullable:false
        ~generated:true
        ()
    ]
  in
  let foreign_key =
    Schema_ir.foreign_key
      ~columns:[ identifier "id" ]
      ~referenced_schema:(identifier "auth")
      ~referenced_table:(identifier "accounts")
      ~referenced_columns:[ identifier "id" ]
      ()
  in
  let unique =
    Schema_ir.unique_constraint
      ~name:(identifier "users_display_name_key")
      [ identifier "display-name" ]
  in
  let table =
    Schema_ir.table
      ~schema:(identifier "public")
      ~name:(identifier "users")
      ~columns
      ~foreign_keys:[ foreign_key ]
      ~unique_constraints:[ unique ]
      ()
  in
  let schema = Schema_ir.v [ table ] in
  assert (List.length (Schema_ir.tables schema) = 1);
  assert (Identifier.equal (Schema_ir.table_name table) (identifier "users"));
  assert (Option.is_some (Schema_ir.table_schema table));
  assert (List.length (Schema_ir.columns table) = 3);
  assert (List.length (Schema_ir.foreign_keys table) = 1);
  assert (List.length (Schema_ir.unique_constraints table) = 1);
  let display_name = List.nth_exn columns 1 in
  assert (
    Identifier.equal (Schema_ir.column_name display_name) (identifier "display-name"));
  (match Schema_ir.column_db_type display_name with
   | Text -> ()
   | _ -> failwith "schema column returned the wrong database type");
  assert (Schema_ir.column_nullable display_name);
  assert (Option.is_some (Schema_ir.column_default display_name));
  assert (not (Schema_ir.column_generated display_name));
  assert (Option.is_none (Schema_ir.column_primary_key_position display_name));
  assert (List.length (Schema_ir.foreign_key_columns foreign_key) = 1);
  assert (Option.is_some (Schema_ir.foreign_key_referenced_schema foreign_key));
  assert (
    Identifier.equal
      (Schema_ir.foreign_key_referenced_table foreign_key)
      (identifier "accounts"));
  assert (List.length (Schema_ir.foreign_key_referenced_columns foreign_key) = 1);
  assert (Option.is_some (Schema_ir.unique_constraint_name unique));
  assert (List.length (Schema_ir.unique_constraint_columns unique) = 1);
  let all_types =
    Schema_ir.table
      ~name:(identifier "123-order")
      ~columns:
        [ Schema_ir.column ~name:(identifier "type") ~db_type:Bool ~nullable:false ()
        ; Schema_ir.column ~name:(identifier "count") ~db_type:Int ~nullable:false ()
        ; Schema_ir.column ~name:(identifier "ratio") ~db_type:Float ~nullable:false ()
        ; Schema_ir.column ~name:(identifier "payload") ~db_type:Bytes ~nullable:false ()
        ; Schema_ir.column
            ~name:(identifier "published_on")
            ~db_type:Date
            ~nullable:false
            ()
        ; Schema_ir.column ~name:(identifier "uuid") ~db_type:Uuid ~nullable:false ()
        ]
      ()
  in
  let collision_column name =
    Schema_ir.column ~name:(identifier name) ~db_type:Text ~nullable:false ()
  in
  let colliding_table =
    Schema_ir.table
      ~name:(identifier "user-profile")
      ~columns:
        [ collision_column "id"
        ; collision_column "id-column"
        ; collision_column "display-name"
        ; collision_column "display_name"
        ; collision_column "display.name"
        ; collision_column "table"
        ]
      ()
  in
  let colliding_module =
    Schema_ir.table
      ~name:(identifier "user_profile")
      ~columns:[ collision_column "id" ]
      ()
  in
  let third_colliding_module =
    Schema_ir.table
      ~name:(identifier "USER PROFILE")
      ~columns:[ collision_column "id" ]
      ()
  in
  let generated =
    Schema_codegen.generate
      (Schema_ir.v
         [ table; all_types; colliding_table; colliding_module; third_colliding_module ])
    |> Result.map_error ~f:Schema_codegen.error_to_string
    |> Result.ok_or_failwith
  in
  assert (String.is_substring generated ~substring:"module Users = struct");
  assert (String.is_substring generated ~substring:"display_name_column");
  assert (String.is_substring generated ~substring:"Db_type.timestamp");
  assert (String.is_substring generated ~substring:"display_name_default");
  assert (String.is_substring generated ~substring:"id_primary_key_position = Some 1");
  assert (String.is_substring generated ~substring:"let foreign_keys");
  assert (String.is_substring generated ~substring:"Some \"auth\"");
  assert (String.is_substring generated ~substring:"let unique_constraints");
  assert (String.is_substring generated ~substring:"module Generated_123_order = struct");
  assert (String.is_substring generated ~substring:"type__column");
  assert (
    String.is_prefix
      generated
      ~prefix:
        "open! Base\nmodule Typed_sql_codegen = Typed_sql\nmodule Typed_sql_codegen_ptime = Ptime\n");
  assert (String.is_substring generated ~substring:"module User_profile = struct");
  assert (String.is_substring generated ~substring:"module User_profile_2 = struct");
  assert (String.is_substring generated ~substring:"module User_profile_3 = struct");
  assert (String.is_substring generated ~substring:"id_column_2_column");
  assert (String.is_substring generated ~substring:"display_name_2_column");
  assert (String.is_substring generated ~substring:"display_name_3_column");
  assert (String.is_substring generated ~substring:"table_2_column");
  let underscore =
    Schema_ir.table
      ~name:(identifier "items")
      ~columns:
        [ Schema_ir.column ~name:(identifier "_") ~db_type:Text ~nullable:false () ]
      ()
  in
  let generated_underscore =
    Schema_codegen.generate (Schema_ir.v [ underscore ])
    |> Result.map_error ~f:Schema_codegen.error_to_string
    |> Result.ok_or_failwith
  in
  assert (String.is_substring generated_underscore ~substring:"field_column");
  Parse.implementation (Lexing.from_string generated) |> ignore;
  let empty_table = Schema_ir.table ~name:(identifier "empty") ~columns:[] () in
  (match Schema_codegen.generate (Schema_ir.v [ empty_table ]) with
   | Error error ->
     assert (
       String.equal (Schema_codegen.error_to_string error) "table empty has no columns")
   | Ok _ -> failwith "empty schema table was generated");
  let unsupported =
    Schema_ir.table
      ~name:(identifier "custom")
      ~columns:
        [ Schema_ir.column
            ~name:(identifier "value")
            ~db_type:(Unsupported "jsonb")
            ~nullable:false
            ()
        ]
      ()
  in
  match Schema_codegen.generate (Schema_ir.v [ unsupported ]) with
  | Error error ->
    assert (
      String.equal
        (Schema_codegen.error_to_string error)
        "unsupported type jsonb for custom.value")
  | Ok _ -> failwith "unsupported schema type was generated"
;;
