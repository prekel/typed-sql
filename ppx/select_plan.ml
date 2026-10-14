open! Base
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

type field =
  { name : string
  ; codec : string
  ; nullable : bool
  }

type parameter =
  { value : Sql.parameter
  ; codec : string
  }

type t =
  { sql : string
  ; fields : field list
  ; parameters : parameter list
  }

let fail offset message = Error { Sql.offset; message }

let codec ~offset column =
  match S.column_postgresql_type column with
  | None ->
    fail
      offset
      ("missing exact PostgreSQL type for column "
       ^ I.to_string (S.column_name column)
       ^ "; refresh the schema snapshot")
  | Some (schema, name) ->
    let schema = I.to_string schema in
    let name = I.to_string name in
    if not (String.equal schema "pg_catalog") then
      fail offset ("unsupported PostgreSQL type: " ^ schema ^ "." ^ name)
    else (
      match
        name
      with
      | "bool" -> Ok "bool"
      | "int2" -> Ok "int16"
      | "int4" -> Ok "int32"
      | "int8" -> Ok "int64"
      | "float4" | "float8" -> Ok "float"
      | "text" | "varchar" | "bpchar" | "numeric" | "json" | "jsonb" -> Ok "string"
      | "bytea" | "date" | "time" | "timestamp" | "timestamptz" | "interval" | "uuid" ->
        Ok name
      | _ -> fail offset ("unsupported PostgreSQL type: " ^ schema ^ "." ^ name))
;;

let create schema (query : Sql.t) =
  let open Result.Let_syntax in
  let%bind table =
    match
      List.filter (S.tables schema) ~f:(fun table ->
        String.equal query.table (I.to_string (S.table_name table))
        && Option.value_map (S.table_schema table) ~default:false ~f:(fun schema ->
          String.equal query.schema (I.to_string schema)))
    with
    | [ table ] -> Ok table
    | [] -> fail 0 ("unknown table: " ^ query.schema ^ "." ^ query.table)
    | _ -> fail 0 ("ambiguous table in snapshot: " ^ query.schema ^ "." ^ query.table)
  in
  let qualifier (reference : Sql.reference) names =
    let valid =
      match names with
      | [] -> true
      | [ name ] -> String.equal name (Option.value query.alias ~default:query.table)
      | [ schema; name ] ->
        Option.is_none query.alias
        && String.equal schema query.schema
        && String.equal name query.table
      | _ -> false
    in
    if valid then
      Ok ()
    else
      fail reference.offset "column qualifier does not name the SELECT source"
  in
  let resolve (reference : Sql.reference) =
    match List.rev reference.names with
    | [] -> fail reference.offset "expected column name"
    | name :: reversed_qualifier ->
      let%bind () = qualifier reference (List.rev reversed_qualifier) in
      (match
         List.filter (S.columns table) ~f:(fun column ->
           String.equal name (I.to_string (S.column_name column)))
       with
       | [ column ] -> Ok column
       | [] -> fail reference.offset ("unknown column: " ^ name)
       | _ -> fail reference.offset ("ambiguous column in snapshot: " ^ name))
  in
  let field ~offset ?name column =
    let%map codec = codec ~offset column in
    { name = Option.value name ~default:(I.to_string (S.column_name column))
    ; codec
    ; nullable = S.column_nullable column
    }
  in
  let%bind fields =
    List.map query.projection ~f:(function
      | Sql.Column (reference, name) ->
        let%bind column = resolve reference in
        let%map field = field ~offset:reference.offset ?name column in
        [ field ]
      | All reference ->
        let%bind () = qualifier reference reference.names in
        List.map (S.columns table) ~f:(field ~offset:reference.offset) |> Result.all)
    |> Result.all
    |> Result.map ~f:List.concat
  in
  let%bind () =
    if List.is_empty fields then
      fail 0 "SELECT must return at least one column"
    else
      Ok ()
  in
  let%bind parameters =
    List.map query.conditions ~f:(fun (reference, value) ->
      let%bind column = resolve reference in
      let%bind () =
        match S.column_postgresql_type column with
        | Some (schema, name)
          when String.equal (I.to_string schema) "pg_catalog"
               && String.equal (I.to_string name) "json" ->
          fail reference.offset "PostgreSQL json has no equality operator; use jsonb"
        | _ -> Ok ()
      in
      let%map codec = codec ~offset:reference.offset column in
      { value; codec })
    |> Result.all
  in
  let%bind () =
    List.map query.order ~f:(fun reference ->
      let%bind column = resolve reference in
      match S.column_postgresql_type column with
      | Some (schema, name)
        when String.equal (I.to_string schema) "pg_catalog"
             && String.equal (I.to_string name) "json" ->
        fail reference.offset "PostgreSQL json has no ordering operator; use jsonb"
      | _ -> Ok ())
    |> Result.all
    |> Result.map ~f:(fun _ -> ())
  in
  let pieces, stop =
    List.foldi parameters ~init:([], 0) ~f:(fun index (pieces, stop) { value; _ } ->
      let text = String.sub query.source ~pos:stop ~len:(value.start - stop) in
      ("$" ^ Int.to_string (index + 1)) :: text :: pieces, value.stop)
  in
  let tail = String.sub query.source ~pos:stop ~len:(String.length query.source - stop) in
  let sql = String.concat (List.rev (tail :: pieces)) in
  Ok { sql; fields; parameters }
;;
