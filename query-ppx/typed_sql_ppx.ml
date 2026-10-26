(* Object method validation follows the compatible generator in ../ppx/expand.ml,
   whose runtime generation is adapted from PG'OCaml 4.4.0 ppx_pgsql.ml.
   Copyright (C) 2005-2016 Richard Jones and other authors.
   Distributed under the GNU Library General Public License, version 2 or later.
   See COPYING and ORIGIN.md. *)
open! Base
open Ppxlib
module B = Ast_builder.Default
module Shared = Typed_sql_ppx_cache
module Query_cache = Shared.Query_cache
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

type registry =
  | Empty
  | One of Query_cache.t
  | Several

let registry = ref Empty

let register_queries cache =
  registry
  := match !registry with
     | Empty -> One cache
     | One _ | Several -> Several
;;

let fail ~loc message = Location.raise_errorf ~loc "typed-sql-ppx: %s" message
let fn ~loc path = B.evar ~loc path

let call ~loc path args =
  B.pexp_apply ~loc (fn ~loc path) (List.map args ~f:(fun e -> Nolabel, e))
;;

let labelled ~loc path args = B.pexp_apply ~loc (fn ~loc path) args

let identifier ~loc name =
  call ~loc "Typed_sql.Identifier.of_string_exn" [ B.estring ~loc name ]
;;

let rec descriptor ~loc (typ : S.postgresql_type_info) =
  let native_name = I.to_string typ.name in
  let named repr =
    labelled
      ~loc
      "Typed_sql.Db_type.Postgresql.named"
      [ Labelled "schema", identifier ~loc (I.to_string typ.schema)
      ; Labelled "name", identifier ~loc native_name
      ; Nolabel, repr
      ]
  in
  let builtin name = fn ~loc ("Typed_sql.Db_type." ^ name) in
  match typ.kind with
  | Native_enum _ -> named (builtin "text")
  | Native_domain base -> named (descriptor ~loc base)
  | Native_array element ->
    call ~loc "Typed_sql.Db_type.Postgresql.array" [ descriptor ~loc element ]
  | Native_scalar when String.equal (I.to_string typ.schema) "pg_catalog" ->
    (match native_name with
     | "bool" -> builtin "bool"
     | "int4" -> builtin "int"
     | "int8" -> builtin "int64"
     | "float8" -> builtin "float"
     | "text" -> builtin "text"
     | "numeric" -> builtin "numeric"
     | "bytea" -> builtin "bytes"
     | "date" -> builtin "date"
     | "timestamptz" -> builtin "timestamp"
     | "timestamp" -> builtin "Postgresql.local_timestamp"
     | "interval" -> builtin "Postgresql.interval"
     | "json" -> builtin "Postgresql.json"
     | "jsonb" -> builtin "Postgresql.jsonb"
     | "uuid" -> builtin "uuid"
     | "int2" -> named (builtin "int")
     | "float4" -> named (builtin "float")
     | "varchar" | "bpchar" | "time" -> named (builtin "text")
     | _ -> fail ~loc ("unsupported PostgreSQL type: pg_catalog." ^ native_name))
  | Native_scalar | Native_opaque ->
    fail
      ~loc
      ("unsupported PostgreSQL type: " ^ I.to_string typ.schema ^ "." ^ native_name)
;;

let nullable ~loc optional typ =
  let typ = descriptor ~loc typ in
  if optional then
    call ~loc "Typed_sql.Db_type.option" [ typ ]
  else
    typ
;;

let valid_method name =
  match
    Result.try_with (fun () ->
      Parse.expression (Stdlib.Lexing.from_string ("object method " ^ name ^ " = () end")))
  with
  | Ok
      { pexp_desc =
          Pexp_object
            { pcstr_fields = [ { pcf_desc = Pcf_method ({ txt; _ }, _, _); _ } ]; _ }
      ; _
      } -> String.equal txt name
  | _ -> false
;;

let output ~loc ~object_ ~nullable_results fields =
  if object_ then (
    let names = List.map fields ~f:(fun f -> f.Query_cache.name) in
    List.iter names ~f:(fun name ->
      if not (valid_method name) then
        fail ~loc ("invalid object method name: " ^ name));
    if Option.is_some (List.find_a_dup names ~compare:String.compare) then
      fail ~loc "duplicate object method name");
  let variables = List.mapi fields ~f:(fun i _ -> "typed_sql_field_" ^ Int.to_string i) in
  let result =
    if object_ then
      B.pexp_object
        ~loc
        { pcstr_self = B.ppat_any ~loc
        ; pcstr_fields =
            List.map2_exn fields variables ~f:(fun field variable ->
              B.pcf_method
                ~loc
                ( { txt = field.Query_cache.name; loc }
                , Public
                , Cfk_concrete (Fresh, fn ~loc variable) ))
        }
    else (
      match
        variables
      with
      | [ variable ] -> fn ~loc variable
      | _ -> B.pexp_tuple ~loc (List.map variables ~f:(fn ~loc)))
  in
  let make =
    List.fold_right variables ~init:result ~f:(fun variable body ->
      B.pexp_fun ~loc Nolabel None (B.pvar ~loc variable) body)
  in
  let initial = call ~loc "Typed_sql.Raw_sql.Output.return" [ make ] in
  List.fold fields ~init:initial ~f:(fun acc field ->
    let field =
      labelled
        ~loc
        "Typed_sql.Raw_sql.Output.field"
        [ Labelled "name", identifier ~loc field.Query_cache.name
        ; Nolabel, nullable ~loc (field.nullable || nullable_results) field.typ
        ]
    in
    labelled
      ~loc
      "Typed_sql.Raw_sql.Output.map2"
      [ Nolabel, acc; Nolabel, field; Labelled "f", [%expr fun f x -> f x] ])
;;

let expand ~object_ ~command ~statement ~loc payload =
  let input, flags, source, sql_loc =
    if statement then
      Shared.Query_source.statement_payload_exn ~loc payload
    else (
      let flags, source, sql_loc =
        Shared.Query_source.payload_exn ~loc ~with_connection:false payload
      in
      None, flags, source, sql_loc)
  in
  let cache =
    match !registry with
    | Empty ->
      fail
        ~loc
        "no query cache is registered; add the generated cache PPX library to (pps ...)"
    | Several -> fail ~loc "multiple query caches are registered"
    | One cache -> cache
  in
  let query =
    match Shared.Query_bind.scan source with
    | Ok query -> query
    | Error error ->
      fail ~loc:sql_loc ("SQL byte " ^ Int.to_string error.offset ^ ": " ^ error.message)
  in
  let entry =
    match Query_cache.find cache ~sql:query.sql with
    | Some entry -> entry
    | None ->
      fail
        ~loc:sql_loc
        "query is absent from the cache; run typed-sql-pgocaml-queries prepare"
  in
  let command =
    if statement then (
      match
        entry.kind
      with
      | Command -> not object_
      | Select | Returning | Unsupported -> false)
    else
      command
  in
  (match entry.kind, command with
   | Unsupported, _ ->
     fail
       ~loc:sql_loc
       "query kind is unavailable or unsupported; refresh the cache with prepare (v2 required)"
   | Command, false ->
     fail
       ~loc:sql_loc
       (if statement then
          "pgsql.statement.object requires returned rows; use pgsql.statement"
        else
          "query quotation requires returned rows; use pgsql.command")
   | (Select | Returning), true ->
     fail ~loc:sql_loc "pgsql.command requires DML without RETURNING"
   | _ -> ());
  if command && not (List.is_empty flags) then
    fail ~loc "command quotation does not accept result flags";
  if not (Int.equal (List.length query.parameters) (List.length entry.parameters)) then
    fail ~loc "cached parameter count mismatch";
  if statement && Option.is_none input && not (List.is_empty query.parameters) then
    fail ~loc "statement parameters require an input pattern: fun input -> SQL";
  if statement && Option.is_some input && List.is_empty query.parameters then
    fail
      ~loc
      "statement input pattern requires at least one SQL parameter; use a SQL literal for unit input";
  let params_name = gen_symbol ~prefix:"typed_sql_params" () in
  let slots =
    List.map query.parameters ~f:(fun _ -> gen_symbol ~prefix:"typed_sql_slot" ())
  in
  let rec pieces first parameters types slots =
    match parameters, types, slots with
    | [], [], [] ->
      let tail = String.sub source ~pos:first ~len:(String.length source - first) in
      let tail =
        match (Shared.Query_kind.analyze query.sql).terminator with
        | None -> tail
        | Some index ->
          let index = index - (String.length query.sql - String.length tail) in
          if
            Int.(index < 0 || index >= String.length tail)
            || not (Char.equal tail.[index] ';')
          then
            fail ~loc "terminal SQL boundary mismatch";
          String.prefix tail index ^ String.drop_prefix tail (index + 1)
      in
      [ call ~loc "Typed_sql.Raw_sql.Postgresql.unsafe_sql" [ B.estring ~loc tail ] ]
    | parameter :: rest, typ :: types, slot :: slots ->
      let text =
        String.sub source ~pos:first ~len:(parameter.Shared.Query_bind.start - first)
      in
      let value =
        if statement then
          fn ~loc slot
        else
          Parse.expression (Stdlib.Lexing.from_string parameter.expression)
      in
      call ~loc "Typed_sql.Raw_sql.Postgresql.unsafe_sql" [ B.estring ~loc text ]
      :: call
           ~loc
           "Typed_sql.Raw_sql.Postgresql.bind"
           [ nullable ~loc parameter.optional typ; value ]
      :: pieces parameter.stop rest types slots
    | _ -> fail ~loc "cached parameter count mismatch"
  in
  let parts = B.elist ~loc (pieces 0 query.parameters entry.parameters slots) in
  let result =
    if command then
      call ~loc "Typed_sql.Raw_sql.Postgresql.command" [ parts ]
    else (
      let fields =
        match entry.result with
        | Some (_ :: _ as fields) -> fields
        | _ -> fail ~loc "missing cached output fields"
      in
      let output =
        output
          ~loc
          ~object_
          ~nullable_results:(List.mem flags "nullable-results" ~equal:String.equal)
          fields
      in
      let args = [ Labelled "output", output; Nolabel, parts ] in
      match entry.kind with
      | Select ->
        labelled
          ~loc
          "Typed_sql.Raw_sql.Postgresql.select"
          ((Labelled "top_level_only", B.ebool ~loc entry.top_level_only) :: args)
      | Returning -> labelled ~loc "Typed_sql.Raw_sql.Postgresql.returning" args
      | _ -> fail ~loc "query output kind invariant")
  in
  if statement then (
    let method_name =
      if command then
        "command"
      else
        "query_many"
    in
    match input with
    | None ->
      labelled
        ~loc
        ("Typed_sql.Statement." ^ method_name)
        [ Labelled "dialect", fn ~loc "Typed_sql.Dialect.postgresql"; Nolabel, result ]
    | Some input ->
      let method_ name =
        B.pexp_field ~loc (fn ~loc params_name) { txt = Lident name; loc }
      in
      let compiled = B.pexp_apply ~loc (method_ method_name) [ Nolabel, result ] in
      let make =
        List.fold_right slots ~init:compiled ~f:(fun slot body ->
          B.pexp_fun ~loc Nolabel None (B.pvar ~loc slot) body)
      in
      let initial = call ~loc "Typed_sql.Parameters.return" [ make ] in
      let declarations =
        List.map2_exn query.parameters entry.parameters ~f:(fun parameter typ ->
          let getter =
            B.pexp_fun
              ~loc
              Nolabel
              None
              input
              (Parse.expression (Stdlib.Lexing.from_string parameter.expression))
          in
          (* Each getter uses only its own part of the shared input pattern. *)
          let getter =
            { getter with
              pexp_attributes =
                [ B.attribute
                    ~loc
                    ~name:{ txt = "warning"; loc }
                    ~payload:(PStr [ B.pstr_eval ~loc (B.estring ~loc "-27") [] ])
                ]
            }
          in
          B.pexp_apply
            ~loc
            (method_ "expr")
            [ Nolabel, nullable ~loc parameter.optional typ; Labelled "get", getter ])
      in
      let body =
        List.fold declarations ~init:initial ~f:(fun acc declaration ->
          labelled
            ~loc
            "Typed_sql.Parameters.map2"
            [ Nolabel, acc; Nolabel, declaration; Labelled "f", [%expr fun f x -> f x] ])
      in
      let callback =
        B.pexp_fun ~loc (Labelled "params") None (B.pvar ~loc params_name) body
      in
      labelled
        ~loc
        "Typed_sql.Statement.with_parameters"
        [ Labelled "dialect", fn ~loc "Typed_sql.Dialect.postgresql"; Nolabel, callback ])
  else
    result
;;

let () =
  let extension name object_ command statement =
    Context_free.Rule.extension
      (Extension.declare
         name
         Extension.Context.expression
         Ast_pattern.__
         (fun ~loc ~path:_ payload -> expand ~object_ ~command ~statement ~loc payload))
  in
  Driver.register_transformation
    "typed_sql_query_ppx"
    ~rules:
      [ extension "pgsql.query" false false false
      ; extension "pgsql.query.object" true false false
      ; extension "pgsql.command" false true false
      ; extension "pgsql.statement" false false true
      ; extension "pgsql.statement.object" true false true
      ]
;;
