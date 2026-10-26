open! Base
open Typed_sql_schema

let identifier = Identifier.of_string_exn

let decode source =
  Schema_snapshot.of_string source
  |> Result.map_error ~f:Schema_snapshot.error_to_string
  |> Result.ok_or_failwith
;;

let%test_module "exact PostgreSQL column types" =
  (module struct
    let native name = identifier "pg_catalog", identifier name

    let schema =
      Schema_ir.v
        [ Schema_ir.table
            ~schema:(identifier "public")
            ~name:(identifier "integers")
            ~columns:
              (List.map
                 [ "small", "int2"; "normal", "int4" ]
                 ~f:(fun (name, native_name) ->
                   Schema_ir.column
                     ~name:(identifier name)
                     ~db_type:Int
                     ~nullable:false
                     ~postgresql_type:(native native_name)
                     ()))
            ()
        ]
    ;;

    let%test_unit "version 3 preserves int2 and int4 without changing descriptors" =
      let restored = decode (Schema_snapshot.to_string schema) in
      let columns = Schema_ir.columns (List.hd_exn (Schema_ir.tables restored)) in
      assert (
        List.equal
          (Option.equal (fun (a, b) (c, d) ->
             Identifier.equal a c && Identifier.equal b d))
          (List.map columns ~f:Schema_ir.column_postgresql_type)
          [ Some (native "int2"); Some (native "int4") ]);
      assert (
        List.for_all columns ~f:(fun column ->
          match Schema_ir.column_db_type column with
          | Int -> true
          | _ -> false));
      let generate value =
        Schema_codegen.generate value
        |> Result.map_error ~f:Schema_codegen.error_to_string
        |> Result.ok_or_failwith
      in
      assert (String.equal (generate schema) (generate restored))
    ;;

    let legacy_json () =
      match Yojson.Safe.from_string (Schema_snapshot.to_string schema) with
      | `Assoc fields ->
        let rec strip : Yojson.Safe.t -> Yojson.Safe.t = function
          | `Assoc fields ->
            `Assoc
              (List.filter_map fields ~f:(fun (name, value) ->
                 if String.equal name "postgresql_type" then
                   None
                 else
                   Some (name, strip value)))
          | `List values -> `List (List.map values ~f:strip)
          | json -> json
        in
        strip (`Assoc (List.Assoc.add fields ~equal:String.equal "version" (`Int 2)))
      | _ -> failwith "snapshot root invariant violated"
    ;;

    let%test_unit "version 2 remains readable and has no invented native types" =
      let restored = decode (Yojson.Safe.to_string (legacy_json ())) in
      assert (
        List.for_all
          (Schema_ir.columns (List.hd_exn (Schema_ir.tables restored)))
          ~f:(fun column -> Option.is_none (Schema_ir.column_postgresql_type column)));
      let generate value =
        Schema_codegen.generate value
        |> Result.map_error ~f:Schema_codegen.error_to_string
        |> Result.ok_or_failwith
      in
      assert (String.equal (generate schema) (generate restored))
    ;;

    let%expect_test "missing exact metadata field is invalid in version 3" =
      let source =
        Yojson.Safe.to_string (legacy_json ())
        |> String.substr_replace_all ~pattern:"\"version\":2" ~with_:"\"version\":3"
      in
      (match Schema_snapshot.of_string source with
       | Error error -> Stdlib.print_endline (Schema_snapshot.error_to_string error)
       | Ok _ -> failwith "version 3 must require the metadata field");
      [%expect {| $.tables[0].columns[0].postgresql_type: missing field |}]
    ;;

    let%expect_test "native type identifiers are validated" =
      let source =
        Schema_snapshot.to_string schema
        |> String.substr_replace_all ~pattern:"\"name\": \"int2\"" ~with_:"\"name\": \"\""
      in
      (match Schema_snapshot.of_string source with
       | Error error -> Stdlib.print_endline (Schema_snapshot.error_to_string error)
       | Ok _ -> failwith "expected invalid native type identifier");
      [%expect
        {| $.tables[0].columns[0].postgresql_type.name: SQL identifier must not be empty |}]
    ;;
  end)
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
        ?postgresql_type:
          (if Int.equal index 0 then
             Some (identifier "pg_catalog", identifier "bool")
           else
             None)
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
  assert (String.is_substring source ~substring:"\"version\": 3");
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
  assert (String.is_substring generated ~substring:"module Type_public_host")
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
  [%expect {| { "version": 3, "tables": [] } |}]
;;

let%expect_test "version 3 table and column wire format" =
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
      "version": 3,
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
              "primary_key_position": 1,
              "postgresql_type": null
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
      print_error {|{"version":1,"tables":[]}|};
      [%expect {| $.version: unsupported snapshot version: 1 |}]
    ;;

    let%expect_test "snapshot reports a duplicate version field" =
      print_error {|{"version":2,"tables":[],"version":2}|};
      [%expect {| $.version: duplicate field |}]
    ;;

    let%expect_test "snapshot reports a missing tables field" =
      print_error {|{"version":2}|};
      [%expect {| $.tables: missing field |}]
    ;;

    let%expect_test "snapshot reports an invalid table name path" =
      print_error
        {|{"version":2,"tables":[{"schema":null,"name":"","columns":[],"foreign_keys":[],"unique_constraints":[]}]}|};
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
  let restored = decode {|{"tables":[],"version":2}|} in
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

let%test "column-scoped rule selects an array element codec" =
  let rules =
    Schema_codegen.rules_of_string
      {|{"version":1,"rules":[{"priority":0,"sql_type":"public[.]custom","column":"objects[.]values","module":"App.Custom"}]}|}
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

let%expect_test "snapshot reports the path of a too-long identifier" =
  let name = String.make 64 'x' in
  let source =
    Stdlib.Printf.sprintf
      {|{"version":2,"tables":[{"schema":null,"name":"%s","columns":[],"foreign_keys":[],"unique_constraints":[]}]}|}
      name
  in
  (match Schema_snapshot.of_string source with
   | Error error -> Stdlib.print_endline (Schema_snapshot.error_to_string error)
   | Ok _ -> failwith "long identifier accepted in schema snapshot");
  [%expect {| $.tables[0].name: SQL identifier must be at most 63 bytes, got 64 |}]
;;

let%test_module "optional nested native metadata in version 3" =
  (module struct
    let info schema name kind : Schema_ir.postgresql_type_info =
      { schema = identifier schema; name = identifier name; kind }
    ;;

    let enum = info "public" "mood" (Native_enum [ "happy"; "sad" ])
    let array = info "public" "_mood" (Native_array enum)
    let domain = info "public" "mood_list" (Native_domain array)

    let schema =
      Schema_ir.v
        [ Schema_ir.table
            ~schema:(identifier "public")
            ~name:(identifier "items")
            ~columns:
              [ Schema_ir.column
                  ~name:(identifier "value")
                  ~db_type:Text
                  ~nullable:false
                  ~postgresql_type:(domain.schema, domain.name)
                  ~postgresql_type_info:domain
                  ~postgresql_attribute_not_null:false
                  ()
              ]
            ()
        ]
    ;;

    let source = Schema_snapshot.to_string schema

    let column value =
      List.hd_exn (Schema_ir.columns (List.hd_exn (Schema_ir.tables value)))
    ;;

    let%test_unit "writer remains version 3 and preserves nested exact identities" =
      (match Yojson.Safe.from_string source with
       | `Assoc fields ->
         (match List.Assoc.find fields "version" ~equal:String.equal with
          | Some (`Int version) -> assert (Int.equal version 3)
          | _ -> failwith "expected snapshot version")
       | _ -> failwith "expected snapshot object");
      let restored = column (decode source) in
      assert (
        Option.equal
          Bool.equal
          (Schema_ir.column_postgresql_attribute_not_null restored)
          (Some false));
      match Schema_ir.column_postgresql_type_info restored with
      | Some
          { name
          ; kind =
              Native_domain
                { name = array_name
                ; kind = Native_array { name = enum_name; kind = Native_enum labels; _ }
                ; _
                }
          ; _
          } ->
        assert (String.equal (Identifier.to_string name) "mood_list");
        assert (String.equal (Identifier.to_string array_name) "_mood");
        assert (String.equal (Identifier.to_string enum_name) "mood");
        assert (List.equal String.equal labels [ "happy"; "sad" ])
      | _ -> failwith "expected domain over enum array"
    ;;

    let%test_unit "optional metadata does not change portable descriptors" =
      let without_metadata =
        Schema_ir.v
          [ Schema_ir.table
              ~schema:(identifier "public")
              ~name:(identifier "items")
              ~columns:
                [ Schema_ir.column
                    ~name:(identifier "value")
                    ~db_type:Text
                    ~nullable:false
                    ~postgresql_type:(domain.schema, domain.name)
                    ()
                ]
              ()
          ]
      in
      let generate value =
        Schema_codegen.generate value
        |> Result.map_error ~f:Schema_codegen.error_to_string
        |> Result.ok_or_failwith
      in
      assert (String.equal (generate schema) (generate without_metadata));
      assert (
        Option.is_none
          (Schema_ir.column_postgresql_type_info
             (column (decode (Schema_snapshot.to_string without_metadata)))))
    ;;

    let change_column f =
      match Yojson.Safe.from_string source with
      | `Assoc root ->
        (match List.Assoc.find root "tables" ~equal:String.equal with
         | Some (`List [ `Assoc table ]) ->
           (match List.Assoc.find table "columns" ~equal:String.equal with
            | Some (`List [ `Assoc fields ]) ->
              let table =
                List.Assoc.add
                  table
                  "columns"
                  (`List [ `Assoc (f fields) ])
                  ~equal:String.equal
              in
              Yojson.Safe.to_string
                (`Assoc
                    (List.Assoc.add
                       root
                       "tables"
                       (`List [ `Assoc table ])
                       ~equal:String.equal))
            | _ -> failwith "expected fixture column")
         | _ -> failwith "expected fixture table")
      | _ -> failwith "expected snapshot object"
    ;;

    let%test "a native type tree must match the exact column type" =
      let source =
        change_column (fun fields ->
          List.Assoc.add
            fields
            "postgresql_type"
            (`Assoc [ "schema", `String "public"; "name", `String "other" ])
            ~equal:String.equal)
      in
      Result.is_error (Schema_snapshot.of_string source)
    ;;

    let%test "attribute flags require a boolean" =
      Result.is_error
        (Schema_snapshot.of_string
           (change_column (fun fields ->
              List.Assoc.add
                fields
                "postgresql_attribute_not_null"
                (`String "false")
                ~equal:String.equal)))
    ;;

    let%test "explicit null extensions are accepted as absent metadata" =
      let restored =
        decode
          (change_column (fun fields ->
             List.Assoc.add
               (List.Assoc.add fields "postgresql_type_info" `Null ~equal:String.equal)
               "postgresql_attribute_not_null"
               `Null
               ~equal:String.equal))
        |> column
      in
      Option.is_none (Schema_ir.column_postgresql_type_info restored)
      && Option.is_none (Schema_ir.column_postgresql_attribute_not_null restored)
    ;;

    let%test "unknown native kinds are rejected" =
      Result.is_error
        (Schema_snapshot.of_string
           (String.substr_replace_all
              source
              ~pattern:"\"kind\": \"domain\""
              ~with_:"\"kind\": \"unknown\""))
    ;;

    let%test "missing domain bases are rejected" =
      let source =
        change_column (fun fields ->
          List.Assoc.add
            fields
            "postgresql_type_info"
            (`Assoc
                [ "schema", `String "public"
                ; "name", `String "mood_list"
                ; "kind", `String "domain"
                ])
            ~equal:String.equal)
      in
      Result.is_error (Schema_snapshot.of_string source)
    ;;
  end)
;;

let%test_module "PostgreSQL type modifiers" =
  (module struct
    let schema modifier =
      Schema_ir.v
        [ Schema_ir.table
            ~schema:(identifier "public")
            ~name:(identifier "items")
            ~columns:
              [ Schema_ir.column
                  ~name:(identifier "value")
                  ~db_type:Text
                  ~nullable:false
                  ~postgresql_type:(identifier "pg_catalog", identifier "varchar")
                  ?postgresql_type_modifier:modifier
                  ()
              ]
            ()
        ]
    ;;

    let column schema =
      List.hd_exn (Schema_ir.columns (List.hd_exn (Schema_ir.tables schema)))
    ;;

    let source = Schema_snapshot.to_string (schema (Some (-1)))

    let%test "missing metadata stays unknown" =
      Option.is_none
        (Schema_ir.column_postgresql_type_modifier
           (column (decode (Schema_snapshot.to_string (schema None)))))
    ;;

    let%test "known unspecified modifier stays minus one" =
      Option.equal
        Int.equal
        (Schema_ir.column_postgresql_type_modifier (column (decode source)))
        (Some (-1))
    ;;

    let%test "declared length survives round trip" =
      Option.equal
        Int.equal
        (Schema_ir.column_postgresql_type_modifier
           (column (decode (Schema_snapshot.to_string (schema (Some 14))))))
        (Some 14)
    ;;

    let%test "null modifier remains unknown" =
      let source =
        String.substr_replace_all
          source
          ~pattern:"\"postgresql_type_modifier\": -1"
          ~with_:"\"postgresql_type_modifier\": null"
      in
      Option.is_none (Schema_ir.column_postgresql_type_modifier (column (decode source)))
    ;;

    let%test "out of range modifier is rejected" =
      let source =
        String.substr_replace_all
          source
          ~pattern:"\"postgresql_type_modifier\": -1"
          ~with_:"\"postgresql_type_modifier\": 2147483648"
      in
      Result.is_error (Schema_snapshot.of_string source)
    ;;

    let%test "noninteger modifier is rejected" =
      let source =
        String.substr_replace_all
          source
          ~pattern:"\"postgresql_type_modifier\": -1"
          ~with_:"\"postgresql_type_modifier\": \"14\""
      in
      Result.is_error (Schema_snapshot.of_string source)
    ;;

    let%test "portable descriptors ignore native modifiers" =
      let generate schema =
        Schema_codegen.generate schema
        |> Result.map_error ~f:Schema_codegen.error_to_string
        |> Result.ok_or_failwith
      in
      String.equal (generate (schema None)) (generate (schema (Some 14)))
    ;;
  end)
;;

let%test_module "PostgreSQL primary key deferrability metadata" =
  (module struct
    let schema flag =
      Schema_ir.v
        [ Schema_ir.table
            ~schema:(identifier "public")
            ~name:(identifier "keys")
            ~columns:
              [ Schema_ir.column
                  ~name:(identifier "id")
                  ~db_type:Int
                  ~nullable:false
                  ~primary_key_position:1
                  ()
              ]
            ?postgresql_primary_key_deferrable:flag
            ()
        ]
    ;;

    let flag schema =
      Schema_ir.postgresql_primary_key_deferrable (List.hd_exn (Schema_ir.tables schema))
    ;;

    let%test_unit "missing metadata stays unknown" =
      let source = Schema_snapshot.to_string (schema None) in
      assert (
        not (String.is_substring source ~substring:"postgresql_primary_key_deferrable"));
      assert (Option.is_none (flag (decode source)))
    ;;

    let%test_unit "immediate PK is distinct from missing metadata" =
      assert (
        Option.equal
          Bool.equal
          (flag (decode (Schema_snapshot.to_string (schema (Some false)))))
          (Some false))
    ;;

    let%test_unit "deferrable PK round trips in version three" =
      let source = Schema_snapshot.to_string (schema (Some true)) in
      assert (String.is_substring source ~substring:"\"version\": 3");
      assert (Option.equal Bool.equal (flag (decode source)) (Some true))
    ;;

    let%test_unit "null deferrability stays unknown" =
      let source =
        Schema_snapshot.to_string (schema (Some true))
        |> String.substr_replace_first
             ~pattern:"\"postgresql_primary_key_deferrable\": true"
             ~with_:"\"postgresql_primary_key_deferrable\": null"
      in
      assert (Option.is_none (flag (decode source)))
    ;;

    let%test "invalid deferrability type rejected" =
      let source =
        Schema_snapshot.to_string (schema (Some true))
        |> String.substr_replace_first
             ~pattern:"\"postgresql_primary_key_deferrable\": true"
             ~with_:"\"postgresql_primary_key_deferrable\": 1"
      in
      Result.is_error (Schema_snapshot.of_string source)
    ;;

    let%test_unit "portable codegen ignores native deferrability" =
      let generate flag =
        Schema_codegen.generate (schema flag)
        |> Result.map_error ~f:Schema_codegen.error_to_string
        |> Result.ok_or_failwith
      in
      assert (String.equal (generate None) (generate (Some false)))
    ;;
  end)
;;
