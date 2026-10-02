open! Base
open Typed_sql_schema

let identifier = Identifier.of_string_exn

let decode source =
  Schema_snapshot.of_string source
  |> Result.map_error ~f:Schema_snapshot.error_to_string
  |> Result.ok_or_failwith
;;

let types =
  [ Schema_ir.Bool; Int; Int64; Float; Numeric; Text; Bytes; Date; Timestamp; Uuid ]
;;

let schema =
  let columns =
    List.mapi types ~f:(fun index db_type ->
      Schema_ir.column
        ~name:(identifier ("field" ^ Int.to_string index))
        ~db_type
        ~nullable:true
        ~default:"'quote \" / \\ / \n / Привет'"
        ~generated:true
        ?primary_key_position:
          (if Int.(index < 2) then
             Some (index + 1)
           else
             None)
        ())
  in
  let keys = [ identifier "field1"; identifier "field0" ] in
  let foreign_key =
    Schema_ir.foreign_key
      ~columns:keys
      ~referenced_schema:(identifier "другая схема")
      ~referenced_table:(identifier "parent\"table")
      ~referenced_columns:[ identifier "b"; identifier "a" ]
      ()
  in
  Schema_ir.v
    [ Schema_ir.table
        ~schema:(identifier "public")
        ~name:(identifier "user-profile")
        ~columns
        ~foreign_keys:[ foreign_key ]
        ~unique_constraints:
          [ Schema_ir.unique_constraint ~name:(identifier "unique") keys
          ; Schema_ir.unique_constraint keys
          ]
        ()
    ; Schema_ir.table
        ~name:(identifier "user_profile")
        ~columns:
          [ Schema_ir.column ~name:(identifier "id") ~db_type:Int ~nullable:false () ]
        ~foreign_keys:
          [ Schema_ir.foreign_key
              ~columns:keys
              ~referenced_table:(identifier "external")
              ~referenced_columns:keys
              ()
          ]
        ()
    ]
;;

let%test_unit "snapshot round trip preserves metadata, types and generated source" =
  let source = Schema_snapshot.to_string schema in
  let restored = decode source in
  assert (String.equal source (Schema_snapshot.to_string restored));
  let generate schema =
    Schema_codegen.generate schema
    |> Result.map_error ~f:Schema_codegen.error_to_string
    |> Result.ok_or_failwith
  in
  assert (String.equal (generate schema) (generate restored));
  let tables = Schema_ir.tables restored in
  assert (
    List.equal
      Identifier.equal
      (List.map tables ~f:Schema_ir.table_name)
      [ identifier "user-profile"; identifier "user_profile" ]);
  let first = List.hd_exn tables in
  let columns = Schema_ir.columns first in
  assert (
    List.equal
      Identifier.equal
      (List.map columns ~f:Schema_ir.column_name)
      (List.init 10 ~f:(fun index -> identifier ("field" ^ Int.to_string index))));
  assert (
    List.equal
      (Option.equal Int.equal)
      (List.map columns ~f:Schema_ir.column_primary_key_position)
      [ Some 1; Some 2; None; None; None; None; None; None; None; None ]);
  let foreign_key = List.hd_exn (Schema_ir.foreign_keys first) in
  assert (
    List.equal
      Identifier.equal
      (Schema_ir.foreign_key_columns foreign_key)
      [ identifier "field1"; identifier "field0" ]);
  assert (
    Option.equal
      Identifier.equal
      (Schema_ir.foreign_key_referenced_schema foreign_key)
      (Some (identifier "другая схема")));
  assert (
    Identifier.equal
      (Schema_ir.foreign_key_referenced_table foreign_key)
      (identifier "parent\"table"));
  assert (
    List.equal
      Identifier.equal
      (Schema_ir.foreign_key_referenced_columns foreign_key)
      [ identifier "b"; identifier "a" ]);
  List.iter columns ~f:(fun column ->
    assert (Schema_ir.column_nullable column);
    assert (Schema_ir.column_generated column);
    assert (
      Option.equal
        String.equal
        (Schema_ir.column_default column)
        (Some "'quote \" / \\ / \n / Привет'")))
;;

let%test_unit "unsupported SQL types survive snapshots for generator diagnostics" =
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~name:(identifier "items")
          ~columns:
            [ Schema_ir.column
                ~name:(identifier "value")
                ~db_type:(Unsupported "custom.\"тип\"")
                ~nullable:false
                ()
            ]
          ()
      ]
  in
  let restored = decode (Schema_snapshot.to_string schema) in
  (match
     Schema_ir.column_db_type
       (List.hd_exn (Schema_ir.columns (List.hd_exn (Schema_ir.tables restored))))
   with
   | Unsupported name -> assert (String.equal name "custom.\"тип\"")
   | _ -> failwith "unsupported type lost");
  match Schema_codegen.generate restored with
  | Error (Unsupported_type { database_type; _ }) ->
    assert (String.equal database_type "custom.\"тип\"")
  | _ -> failwith "expected unsupported type diagnostic"
;;

let%test_unit "structured PostgreSQL types survive snapshot round trip" =
  let schema_id = identifier "public" in
  let enum =
    Schema_ir.Enum
      { schema = schema_id; name = identifier "mood"; labels = [ "happy"; "sad" ] }
  in
  let domain =
    Schema_ir.Domain { schema = schema_id; name = identifier "mood_domain"; base = enum }
  in
  let nested =
    Schema_ir.Array
      (Schema_ir.Domain
         { schema = schema_id
         ; name = identifier "host"
         ; base =
             Schema_ir.Named
               { schema = identifier "pg_catalog"; name = identifier "inet" }
         })
  in
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~schema:schema_id
          ~name:(identifier "rich")
          ~columns:
            (List.mapi
               [ enum; domain; nested; Timestamp_without_timezone; Interval; Json; Jsonb ]
               ~f:(fun index db_type ->
                 Schema_ir.column
                   ~name:(identifier ("field" ^ Int.to_string index))
                   ~db_type
                   ~nullable:false
                   ()))
          ()
      ]
  in
  let source = Schema_snapshot.to_string schema in
  assert (String.is_substring source ~substring:"\"version\": 2");
  assert (String.equal source (Schema_snapshot.to_string (decode source)));
  let rules =
    Schema_codegen.rules_of_string
      {|{"version":1,"rules":[{"priority":0,"sql_type":"pg_catalog[.]inet","column":null,"module":"App.Inet"}]}|}
    |> Result.ok_or_failwith
  in
  let generated =
    Schema_codegen.generate ~rules (decode source)
    |> Result.map_error ~f:Schema_codegen.error_to_string
    |> Result.ok_or_failwith
  in
  assert (String.is_substring generated ~substring:"module Type_public_mood");
  assert (String.is_substring generated ~substring:"module Type_public_host");
  assert (List.is_empty (Schema_ir.tables (decode {|{"version":1,"tables":[]}|})))
;;

let%test_unit "type rules choose priority, column and built-in overrides" =
  let rules =
    Schema_codegen.rules_of_string
      {|{
         "version": 1,
         "rules": [
           {"priority": 0, "sql_type": "integer", "column": null, "module": "App.All"},
           {"priority": 10, "sql_type": "integer", "column": "public[.]items[.]special", "module": "App.Special"}
         ]
       }|}
    |> Result.ok_or_failwith
  in
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~schema:(identifier "public")
          ~name:(identifier "items")
          ~columns:
            [ Schema_ir.column
                ~name:(identifier "ordinary")
                ~db_type:Int
                ~nullable:false
                ()
            ; Schema_ir.column
                ~name:(identifier "special")
                ~db_type:Int
                ~nullable:false
                ()
            ]
          ()
      ]
  in
  let source =
    Schema_codegen.generate ~rules schema
    |> Result.map_error ~f:Schema_codegen.error_to_string
    |> Result.ok_or_failwith
  in
  assert (
    String.is_substring
      source
      ~substring:
        "ordinary_column = Typed_sql_codegen.Column.v_exn table \"ordinary\" (App.All.db_type)");
  assert (
    String.is_substring
      source
      ~substring:
        "special_column = Typed_sql_codegen.Column.v_exn table \"special\" (App.Special.db_type)");
  match
    Schema_codegen.rules_of_string
      {|{"version":1,"rules":[{"priority":0,"sql_type":"[","column":null,"module":"App.Bad"}]}|}
  with
  | Error _ -> ()
  | Ok _ -> failwith "malformed rule regexp was accepted"
;;

let%test "type rules reject invalid shape and module names" =
  List.for_all
    [ "[]"
    ; "{"
    ; {|{"version":2,"rules":[]}|}
    ; {|{"version":1}|}
    ; {|{"version":1,"rules":{}}|}
    ; {|{"version":1,"rules":[null]}|}
    ; {|{"version":1,"rules":[{"priority":"high","sql_type":"integer","column":null,"module":"App.Codec"}]}|}
    ; {|{"version":1,"rules":[{"priority":0,"sql_type":1,"column":null,"module":"App.Codec"}]}|}
    ; {|{"version":1,"rules":[{"priority":0,"sql_type":"integer","column":1,"module":"App.Codec"}]}|}
    ; {|{"version":1,"rules":[{"priority":0,"sql_type":"integer","column":null,"module":1}]}|}
    ; {|{"version":1,"rules":[{"priority":0,"sql_type":null,"column":null,"module":"App.Codec"}]}|}
    ; {|{"version":1,"rules":[{"priority":0,"sql_type":"integer","column":null,"module":"app.codec"}]}|}
    ; {|{"version":1,"rules":[{"priority":0,"sql_type":"integer","column":null,"module":"App.Codec","extra":1}]}|}
    ; {|{"version":1,"rules":[{"priority":0,"sql_type":"integer","column":null,"module":"App.Codec","module":"App.Other"}]}|}
    ]
    ~f:(fun source -> Result.is_error (Schema_codegen.rules_of_string source))
;;

let%test "type rules match a named array element" =
  let rules =
    Schema_codegen.rules_of_string
      {|{"version":1,"rules":[{"priority":0,"sql_type":"public[.]custom","column":null,"module":"App.Custom"}]}|}
    |> Result.ok_or_failwith
  in
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~name:(identifier "objects")
          ~columns:
            [ Schema_ir.column
                ~name:(identifier "values")
                ~db_type:
                  (Array
                     (Named { schema = identifier "public"; name = identifier "custom" }))
                ~nullable:false
                ()
            ]
          ()
      ]
  in
  match Schema_codegen.generate ~rules schema with
  | Error _ -> false
  | Ok source ->
    String.is_substring
      source
      ~substring:"Typed_sql_codegen.Db_type.Postgresql.array (App.Custom.db_type)"
;;

let%test "generator rejects an empty enum and unknown domain base" =
  let named schema name =
    Schema_ir.Named { schema = identifier schema; name = identifier name }
  in
  let schema db_type =
    Schema_ir.v
      [ Schema_ir.table
          ~name:(identifier "objects")
          ~columns:
            [ Schema_ir.column ~name:(identifier "value") ~db_type ~nullable:false () ]
          ()
      ]
  in
  let empty_enum =
    Schema_ir.Enum
      { schema = identifier "public"; name = identifier "empty"; labels = [] }
  in
  let unknown_domain =
    Schema_ir.Domain
      { schema = identifier "public"
      ; name = identifier "wrapped"
      ; base = named "public" "unknown"
      }
  in
  (match Schema_codegen.generate (schema empty_enum) with
   | Error error ->
     String.is_prefix (Schema_codegen.error_to_string error) ~prefix:"invalid type rules:"
   | Ok _ -> false)
  && Result.is_error (Schema_codegen.generate (schema unknown_domain))
;;

let%test "column-only type rule selects a built-in descriptor" =
  let rules =
    Schema_codegen.rules_of_string
      {|{"version":1,"rules":[{"priority":0,"sql_type":null,"column":"objects[.]value","module":"App.Value"}]}|}
    |> Result.ok_or_failwith
  in
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~name:(identifier "objects")
          ~columns:
            [ Schema_ir.column ~name:(identifier "value") ~db_type:Text ~nullable:false ()
            ]
          ()
      ]
  in
  match Schema_codegen.generate ~rules schema with
  | Error _ -> false
  | Ok source -> String.is_substring source ~substring:"App.Value.db_type"
;;

let%test "equal-priority type rules keep file order" =
  let rules =
    Schema_codegen.rules_of_string
      {|{"version":1,"rules":[{"priority":4,"sql_type":"text","column":null,"module":"App.First"},{"priority":4,"sql_type":"text","column":null,"module":"App.Second"}]}|}
    |> Result.ok_or_failwith
  in
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~name:(identifier "objects")
          ~columns:
            [ Schema_ir.column ~name:(identifier "value") ~db_type:Text ~nullable:false ()
            ]
          ()
      ]
  in
  match Schema_codegen.generate ~rules schema with
  | Error _ -> false
  | Ok source ->
    String.is_substring source ~substring:"App.First.db_type"
    && not (String.is_substring source ~substring:"App.Second.db_type")
;;

let%test "one domain module serves repeated columns and ignores column-only base rules" =
  let rules =
    Schema_codegen.rules_of_string
      {|{"version":1,"rules":[{"priority":0,"sql_type":"text","column":"objects[.]first","module":"App.First"}]}|}
    |> Result.ok_or_failwith
  in
  let domain =
    Schema_ir.Domain
      { schema = identifier "public"; name = identifier "alias"; base = Text }
  in
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~name:(identifier "objects")
          ~columns:
            [ Schema_ir.column
                ~name:(identifier "first")
                ~db_type:domain
                ~nullable:false
                ()
            ; Schema_ir.column
                ~name:(identifier "second")
                ~db_type:domain
                ~nullable:false
                ()
            ]
          ()
      ]
  in
  match Schema_codegen.generate ~rules schema with
  | Error _ -> false
  | Ok source ->
    Int.equal
      (List.length
         (String.substr_index_all
            source
            ~may_overlap:false
            ~pattern:"module Type_public_alias"))
      1
;;

let%expect_test "empty snapshot format" =
  Stdlib.print_string (Schema_snapshot.to_string (Schema_ir.v []));
  [%expect {| { "version": 2, "tables": [] } |}]
;;

let%expect_test "version 2 table and column wire format" =
  let schema =
    Schema_ir.v
      [ Schema_ir.table
          ~schema:(identifier "public")
          ~name:(identifier "people")
          ~columns:
            [ Schema_ir.column
                ~name:(identifier "id")
                ~db_type:Int64
                ~nullable:false
                ~primary_key_position:1
                ()
            ]
          ()
      ]
  in
  Stdlib.print_string (Schema_snapshot.to_string schema);
  [%expect
    {|
    {
      "version": 2,
      "tables": [
        {
          "schema": "public",
          "name": "people",
          "columns": [
            {
              "name": "id",
              "db_type": { "kind": "int64" },
              "nullable": false,
              "default": null,
              "generated": false,
              "primary_key_position": 1
            }
          ],
          "foreign_keys": [],
          "unique_constraints": []
        }
      ]
    }
    |}]
;;

let%test_module "snapshot diagnostic paths" =
  (module struct
    let print_error source =
      match Schema_snapshot.of_string source with
      | Error error -> Stdlib.print_endline (Schema_snapshot.error_to_string error)
      | Ok _ -> failwith "expected invalid snapshot"
    ;;

    let%expect_test "unsupported version path" =
      print_error {|{"version":3,"tables":[]}|};
      [%expect {| $.version: unsupported snapshot version: 3 |}]
    ;;

    let%expect_test "snapshot reports a duplicate version field" =
      print_error {|{"version":1,"tables":[],"version":1}|};
      [%expect {| $.version: duplicate field |}]
    ;;

    let%expect_test "snapshot reports a missing tables field" =
      print_error {|{"version":1}|};
      [%expect {| $.tables: missing field |}]
    ;;

    let%expect_test "snapshot reports an invalid table name path" =
      print_error
        {|{"version":1,"tables":[{"schema":null,"name":"","columns":[],"foreign_keys":[],"unique_constraints":[]}]}|};
      [%expect {| $.tables[0].name: SQL identifier must not be empty |}]
    ;;
  end)
;;

let assert_rejected source =
  match Schema_snapshot.of_string source with
  | Error error ->
    assert (String.is_prefix (Schema_snapshot.error_to_string error) ~prefix:"$")
  | Ok _ -> failwith ("invalid snapshot accepted: " ^ source)
;;

let%test_unit "invalid JSON, identifiers, version and type tags are rejected" =
  List.iter
    [ "{"
    ; ""
    ; "{} {}"
    ; "[]"
    ; {|{"version":1.5,"tables":[]}|}
    ; {|{"version":9223372036854775808,"tables":[]}|}
    ]
    ~f:assert_rejected;
  let source = Schema_snapshot.to_string schema in
  List.iter
    [ "\"kind\": \"bool\"", "\"kind\": \"mystery\""
    ; "\"name\": \"field0\"", "\"name\": \"a\\u0000b\""
    ; "\"kind\": \"bool\"", "\"kind\": \"unsupported\""
    ]
    ~f:(fun (pattern, with_) ->
      assert_rejected (String.substr_replace_all source ~pattern ~with_));
  let restored = decode {|{"tables":[],"version":1}|} in
  assert (List.is_empty (Schema_ir.tables restored))
;;

let%test_unit
    "every nested object rejects missing, duplicate, unknown and mistyped fields"
  =
  let json = Yojson.Safe.from_string (Schema_snapshot.to_string schema) in
  let rec mutations : Yojson.Safe.t -> Yojson.Safe.t list = function
    | `Assoc fields ->
      let missing =
        List.map fields ~f:(fun (key, _) ->
          `Assoc (List.filter fields ~f:(fun (other, _) -> not (String.equal key other))))
      in
      let duplicates = List.map fields ~f:(fun field -> `Assoc (field :: fields)) in
      let children =
        List.concat_map fields ~f:(fun (key, value) ->
          List.map (mutations value) ~f:(fun replacement ->
            `Assoc
              (List.map fields ~f:(fun (other, original) ->
                 ( other
                 , if String.equal key other then
                     replacement
                   else
                     original )))))
      in
      `Bool false
      :: `Assoc (("unexpected", `Null) :: fields)
      :: (missing @ duplicates @ children)
    | `List values ->
      `Bool false
      :: List.concat_mapi values ~f:(fun index value ->
        List.map (mutations value) ~f:(fun replacement ->
          `List
            (List.mapi values ~f:(fun other original ->
               if Int.(index = other) then
                 replacement
               else
                 original))))
    | `String _ -> [ `Int 42 ]
    | `Bool _ -> [ `String "true" ]
    | `Int _ -> [ `String "1" ]
    | `Null -> [ `Bool true ]
    | _ -> failwith "unexpected fixture JSON"
  in
  List.iter (mutations json) ~f:(fun json -> assert_rejected (Yojson.Safe.to_string json))
;;
