open! Base
module Shared = Typed_sql_ppx_cache.Query_cache
module Type_info = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

type kind = Shared.kind =
  | Select
  | Returning
  | Command
  | Unsupported

type field = Shared.field =
  { name : string
  ; typ : Type_info.postgresql_type_info
  ; nullable : bool
  }

type entry = Shared.entry =
  { sql : string
  ; kind : kind
  ; top_level_only : bool
  ; parameters : Type_info.postgresql_type_info list
  ; result : field list option
  }

type t = Shared.t

let builtin_codec (typ : Type_info.postgresql_type_info) =
  let name = I.to_string typ.name in
  let stem =
    match typ.kind, name with
    | Native_scalar, "bool" -> Some "bool"
    | Native_scalar, "int2" -> Some "int16"
    | Native_scalar, "int4" -> Some "int32"
    | Native_scalar, "int8" -> Some "int64"
    | Native_scalar, ("float4" | "float8") -> Some "float"
    | Native_scalar, ("text" | "varchar" | "bpchar" | "numeric" | "json" | "jsonb") ->
      Some "string"
    | ( Native_scalar
      , (( "bytea"
         | "date"
         | "time"
         | "timestamp"
         | "timestamptz"
         | "interval"
         | "uuid"
         | "inet" ) as name) ) -> Some name
    | _ -> None
  in
  match stem with
  | Some stem -> Ok (Codec.Scalar stem)
  | None -> Error ("unsupported PostgreSQL type: pg_catalog." ^ name)
;;

let rec codec (typ : Type_info.postgresql_type_info) =
  match typ.kind with
  | Native_array element ->
    let open Result.Let_syntax in
    let%map element = codec element in
    Codec.Array element
  | Native_scalar | Native_enum _ | Native_domain _ | Native_opaque ->
    if String.equal (I.to_string typ.schema) "pg_catalog" then
      builtin_codec typ
    else (
      let name = I.to_string typ.name in
      if
        String.for_all name ~f:(fun char ->
          Char.is_alphanum char || Char.equal char '_' || Char.equal char '\'')
      then
        Ok (Codec.Scalar name)
      else
        Error
          ("PostgreSQL type "
           ^ I.to_string typ.schema
           ^ "."
           ^ name
           ^ " cannot form an OCaml converter name; expected only ASCII letters, digits, underscores or apostrophes"
          ))
;;

let validate cache =
  let open Result.Let_syntax in
  let%map () =
    List.fold_result (Shared.entries cache) ~init:() ~f:(fun () entry ->
      let types =
        entry.parameters
        @ Option.value_map
            entry.result
            ~default:[]
            ~f:(List.map ~f:(fun field -> field.typ))
      in
      List.fold_result types ~init:() ~f:(fun () typ ->
        let%map _ = codec typ in
        ()))
  in
  cache
;;

let create ~role ~search_path entries =
  let open Result.Let_syntax in
  let%bind cache = Shared.create ~role ~search_path entries in
  validate cache
;;

let of_string source =
  let open Result.Let_syntax in
  let%bind cache = Shared.of_string source in
  validate cache
;;

let to_string = Shared.to_string
let codegen cache = Shared.codegen ~target:`Pgocaml_ppx cache

let plan t (query : Query_bind.t) =
  let fail message = Error { Query_bind.offset = 0; message } in
  let open Result.Let_syntax in
  let%bind entry =
    match Shared.find t ~sql:query.sql with
    | Some entry -> Ok entry
    | None ->
      fail
        "query is absent from the cache; run typed-sql-pgocaml-queries prepare to refresh it"
  in
  let%bind pairs =
    match List.zip query.parameters entry.parameters with
    | Ok pairs -> Ok pairs
    | Unequal_lengths ->
      fail "cached parameter count does not match the quotation; refresh the query cache"
  in
  let to_codec typ =
    codec typ |> Result.map_error ~f:(fun message -> { Query_bind.offset = 0; message })
  in
  let%bind parameters =
    List.map pairs ~f:(fun (value, typ) ->
      let%map codec = to_codec typ in
      { Statement_plan.value; codec })
    |> Result.all
  in
  let%map result =
    match entry.result with
    | None -> Ok Statement_plan.Command
    | Some fields ->
      let%map fields =
        List.map fields ~f:(fun field ->
          let%map codec = to_codec field.typ in
          { Statement_plan.name = field.name; codec; nullable = field.nullable })
        |> Result.all
      in
      Statement_plan.Rows fields
  in
  { Statement_plan.sql = query.sql; parameters; result }
;;
