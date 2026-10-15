(* Runtime generation is adapted from PG'OCaml 4.4.0 ppx_pgsql.ml.
   Copyright (C) 2005-2016 Richard Jones and other authors.
   Distributed under the GNU Library General Public License, version 2 or later.
   See COPYING and ORIGIN.md. *)
open! Base
open Ppxlib
module B = Ast_builder.Default

let error ~loc message = Location.raise_errorf ~loc "typed-sql-pgocaml-ppx: %s" message
let name ~loc name = B.evar ~loc name
let apply ~loc fn value = B.pexp_apply ~loc fn [ Nolabel, value ]
let pg ~loc function_name = name ~loc ("PGOCaml." ^ function_name)
let string ~loc value = B.estring ~loc value

let bind ~loc variable value body =
  B.pexp_let
    ~loc
    Nonrecursive
    [ B.value_binding ~loc ~pat:(B.pvar ~loc variable) ~expr:value ]
    body
;;

let snapshot ~loc =
  (match Stdlib.Sys.getenv_opt "PGCUSTOM_CONVERTERS_CONFIG" with
   | Some config when not (String.is_empty config) ->
     error ~loc "custom converter config is not supported yet"
   | _ -> ());
  Schema_registry.current ~loc
;;

let payload ~loc = function
  | PStr [ { pstr_desc = Pstr_eval (expression, []); _ } ] ->
    let dbh, arguments =
      match expression.pexp_desc with
      | Pexp_apply (dbh, arguments) -> dbh, arguments
      | _ -> error ~loc "expected a connection, optional flags and a SQL literal"
    in
    let arguments =
      List.map arguments ~f:(function
        (* PR #80: accept both ordinary and delimited OCaml string constants. *)
        | ( Nolabel
          , { pexp_desc = Pexp_constant (Pconst_string (value, _, _)); pexp_loc; _ } ) ->
          value, pexp_loc
        | _, expression ->
          error ~loc:expression.pexp_loc "expected an unlabelled string literal")
    in
    (match List.rev arguments with
     | (sql, sql_loc) :: flags -> dbh, List.rev_map flags ~f:fst, sql, sql_loc
     | [] -> error ~loc "missing SQL literal")
  | _ -> error ~loc "expected a PG'OCaml expression quotation"
;;

let rec encoder ~loc = function
  | Codec.Scalar codec -> pg ~loc ("string_of_" ^ codec)
  | Array element ->
    apply
      ~loc
      (name ~loc "Typed_sql_pgocaml_runtime.string_of_array")
      (encoder ~loc element)
;;

let rec decoder ~loc = function
  | Codec.Scalar codec -> pg ~loc (codec ^ "_of_string")
  | Array element ->
    let raw = gen_symbol ~prefix:"typed_sql_array_" () in
    let decode = decoder ~loc element in
    [%expr
      fun [%p B.pvar ~loc raw] ->
        match Typed_sql_pgocaml_runtime.array_of_string [%e name ~loc raw] with
        | Stdlib.Result.Ok values ->
          Stdlib.List.map (Stdlib.Option.map [%e decode]) values
        | Stdlib.Result.Error message -> Stdlib.raise (PGOCaml.Error message)]
;;

let generate ~loc ~genobject ~nullable_results dbh (plan : Statement_plan.t) =
  let fresh () = gen_symbol ~prefix:"typed_sql_pgsql_" () in
  let conn = fresh () in
  let params = fresh () in
  let hash = fresh () in
  let rows = fresh () in
  let conn_expr = name ~loc conn in
  let params_expr = name ~loc params in
  let hash_expr = name ~loc hash in
  let prepared_name =
    "ppx_pgsql." ^ Stdlib.Digest.to_hex (Stdlib.Digest.string plan.sql)
  in
  let prepare_name = string ~loc prepared_name in
  let query = string ~loc plan.sql in
  let parameters =
    List.map plan.parameters ~f:(fun { Statement_plan.value; codec } ->
      let expression = Parse.expression (Stdlib.Lexing.from_string value.expression) in
      let expression = { expression with pexp_loc = loc } in
      let encode = encoder ~loc codec in
      if value.optional then
        [%expr Stdlib.Option.map [%e encode] [%e expression]]
      else
        [%expr Stdlib.Option.Some [%e apply ~loc encode expression]])
  in
  let fields = Statement_plan.fields plan in
  let variables = List.map fields ~f:(fun _ -> fresh ()) in
  let values =
    List.map2_exn fields variables ~f:(fun field variable ->
      let decoder = decoder ~loc field.codec in
      let raw = name ~loc variable in
      let value = fresh () in
      let decoded = apply ~loc decoder (name ~loc value) in
      if field.nullable || nullable_results then
        [%expr
          match [%e raw] with
          | Stdlib.Option.None -> Stdlib.Option.None
          | Stdlib.Option.Some [%p B.pvar ~loc value] -> Stdlib.Option.Some [%e decoded]]
      else
        [%expr
          match [%e raw] with
          | Stdlib.Option.Some [%p B.pvar ~loc value] -> [%e decoded]
          | Stdlib.Option.None ->
            Stdlib.failwith
              "ppx_pgsql's nullability heuristic has failed - use \"nullable-results\""])
  in
  let decoded =
    if genobject then (
      let methods =
        List.map2_exn fields values ~f:(fun field value ->
          { pcf_desc =
              Pcf_method ({ txt = field.name; loc }, Public, Cfk_concrete (Fresh, value))
          ; pcf_loc = loc
          ; pcf_attributes = []
          })
      in
      B.pexp_object ~loc { pcstr_self = B.ppat_any ~loc; pcstr_fields = methods })
    else (
      match
        values
      with
      | [] -> [%expr ()]
      | [ value ] -> value
      | _ -> B.pexp_tuple ~loc values)
  in
  let row_pattern =
    List.fold_right
      variables
      ~init:[%pat? []]
      ~f:(fun variable tail -> [%pat? [%p B.pvar ~loc variable] :: [%p tail]])
  in
  let row = fresh () in
  let decode =
    B.pexp_fun
      ~loc
      Nolabel
      None
      (B.pvar ~loc row)
      [%expr
        match [%e name ~loc row] with
        | [%p row_pattern] -> [%e decoded]
        | _ ->
          Stdlib.raise
            (PGOCaml.Error "ppx_pgsql: incorrect number of columns returned from query")]
  in
  let rows_pattern, result =
    match plan.result with
    | Statement_plan.Command -> B.ppat_any ~loc, [%expr ()]
    | Rows _ ->
      B.pvar ~loc rows, [%expr Stdlib.List.rev_map [%e decode] [%e name ~loc rows]]
  in
  let execution =
    [%expr
      PGOCaml.bind
        (if Stdlib.Hashtbl.mem [%e hash_expr] [%e prepare_name] then
           PGOCaml.return ()
         else
           PGOCaml.bind
             (PGOCaml.prepare [%e conn_expr] ~name:[%e prepare_name] ~query:[%e query] ())
             (fun () ->
                Stdlib.Hashtbl.add [%e hash_expr] [%e prepare_name] true;
                PGOCaml.return ()))
        (fun () ->
           PGOCaml.bind
             (PGOCaml.execute_rev
                [%e conn_expr]
                ~name:[%e prepare_name]
                ~params:[%e params_expr]
                ())
             (fun [%p rows_pattern] -> PGOCaml.return [%e result]))]
  in
  let private_data =
    [%expr
      try PGOCaml.private_data [%e conn_expr] with
      | Stdlib.Not_found ->
        let [%p B.pvar ~loc hash] = Stdlib.Hashtbl.create 17 in
        PGOCaml.set_private_data [%e conn_expr] [%e hash_expr];
        [%e hash_expr]]
  in
  bind
    ~loc
    conn
    dbh
    (bind ~loc params (B.elist ~loc parameters) (bind ~loc hash private_data execution))
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

let expand ~genobject ~loc payload_ =
  let dbh, flags, sql, sql_loc = payload ~loc payload_ in
  List.iter flags ~f:(fun flag ->
    if not (String.equal flag "nullable-results") then
      error ~loc ("unsupported flag: " ^ flag));
  let schema = snapshot ~loc:sql_loc in
  let plan =
    let open Result.Let_syntax in
    let%bind sql = Sql.parse sql in
    Statement_plan.create schema sql
  in
  let plan =
    match plan with
    | Ok plan -> plan
    | Error diagnostic -> error ~loc:sql_loc (Sql.error_to_string diagnostic)
  in
  if genobject then (
    let fields = Statement_plan.fields plan in
    if List.is_empty fields then
      error ~loc:sql_loc "pgsql.object requires RETURNING for a DML command";
    let rec validate seen = function
      | [] -> ()
      | field :: rest ->
        if not (valid_method field.Statement_plan.name) then
          error ~loc:sql_loc ("invalid object method name: " ^ field.name);
        if List.mem seen field.name ~equal:String.equal then
          error ~loc:sql_loc ("duplicate object method name: " ^ field.name);
        validate (field.name :: seen) rest
    in
    validate [] fields);
  generate
    ~loc
    ~genobject
    ~nullable_results:(List.mem flags "nullable-results" ~equal:String.equal)
    dbh
    plan
;;

let register () =
  let extension extension_name genobject =
    Extension.declare
      extension_name
      Extension.Context.expression
      Ast_pattern.__
      (fun ~loc ~path:_ payload -> expand ~genobject ~loc payload)
  in
  Driver.register_transformation
    "typed_sql_pgocaml_ppx"
    ~rules:
      [ Context_free.Rule.extension (extension "pgsql" false)
      ; Context_free.Rule.extension (extension "pgsql.object" true)
      ]
;;
