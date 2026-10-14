open! Base
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

type t =
  | Scalar of string
  | Enum of string * string
  | Array of t

let scalar_codec = function
  | "bool" -> Some "bool"
  | "int2" -> Some "int16"
  | "int4" -> Some "int32"
  | "int8" -> Some "int64"
  | "float4" | "float8" -> Some "float"
  | "text" | "varchar" | "bpchar" | "numeric" | "json" | "jsonb" -> Some "string"
  | ("bytea" | "date" | "time" | "timestamp" | "timestamptz" | "interval" | "uuid") as
    name -> Some name
  | _ -> None
;;

let rec codec = function
  | Scalar name ->
    (match scalar_codec name with
     | Some name -> Codec.Scalar name
     | None ->
       failwith "native type invariant: unsupported scalar reached codec generation")
  | Enum _ -> Codec.Scalar "string"
  | Array element -> Codec.Array (codec element)
;;

let fail offset message = Error { Sql.offset; message }

let rec of_info ~offset (info : S.postgresql_type_info) =
  let schema = I.to_string info.schema in
  let name = I.to_string info.name in
  let open Result.Let_syntax in
  match info.kind with
  | Native_enum _ -> Ok (Enum (schema, name))
  | Native_domain base -> of_info ~offset base
  | Native_array element ->
    let%map element = of_info ~offset element in
    Array element
  | Native_scalar
    when String.equal schema "pg_catalog" && Option.is_some (scalar_codec name) ->
    Ok (Scalar name)
  | Native_scalar | Native_opaque ->
    fail offset ("unsupported PostgreSQL type: " ^ schema ^ "." ^ name)
;;

let of_column ~offset column =
  match S.column_postgresql_type_info column with
  | Some info ->
    (match S.column_postgresql_type column with
     | Some (schema, name) when I.equal schema info.schema && I.equal name info.name ->
       of_info ~offset info
     | _ -> fail offset "native type tree does not match the exact column type")
  | None ->
    (match S.column_postgresql_type column with
     | Some (schema, name)
       when String.equal (I.to_string schema) "pg_catalog"
            && Option.is_some (scalar_codec (I.to_string name)) ->
       Ok (Scalar (I.to_string name))
     | Some (schema, name) ->
       fail
         offset
         ("unsupported PostgreSQL type: "
          ^ I.to_string schema
          ^ "."
          ^ I.to_string name
          ^ "; refresh snapshot with nested native metadata")
     | None ->
       fail
         offset
         ("missing exact PostgreSQL type for column "
          ^ I.to_string (S.column_name column)
          ^ "; refresh the schema snapshot"))
;;

let rec equal left right =
  match left, right with
  | Scalar left, Scalar right -> String.equal left right
  | Enum (ls, ln), Enum (rs, rn) -> String.equal ls rs && String.equal ln rn
  | Array left, Array right -> equal left right
  | _ -> false
;;

let text = function
  | Scalar ("text" | "varchar" | "bpchar") -> true
  | _ -> false
;;

let numeric = function
  | Scalar ("int2" | "int4" | "int8" | "float4" | "float8" | "numeric") -> true
  | _ -> false
;;

let rec comparable = function
  | Scalar "json" -> false
  | Scalar _ | Enum _ -> true
  | Array element -> comparable element
;;

let compatible left right =
  equal left right || (text left && text right) || (numeric left && numeric right)
;;

let common left right =
  if equal left right then
    Some left
  else if text left && text right then
    Some (Scalar "text")
  else if numeric left && numeric right then (
    let rank = function
      | Scalar "int2" -> 0
      | Scalar "int4" -> 1
      | Scalar "int8" -> 2
      | Scalar "numeric" -> 3
      | Scalar "float4" -> 4
      | Scalar "float8" -> 5
      | _ -> -1
    in
    Some
      (if Int.(rank left >= rank right) then
         left
       else
         right))
  else
    None
;;
