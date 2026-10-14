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

type result =
  | Command
  | Rows of field list

type t =
  { sql : string
  ; result : result
  ; parameters : parameter list
  }

let fields plan =
  match plan.result with
  | Command -> []
  | Rows fields -> fields
;;

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
      fail reference.offset "column qualifier does not name the statement source"
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
  let resolve_excluded (reference : Sql.reference) =
    match reference.names with
    | [ "excluded"; name ] -> resolve { reference with names = [ name ] }
    | _ -> fail reference.offset "expected EXCLUDED.column"
  in
  let unique_columns references =
    let rec loop seen = function
      | [] -> Ok ()
      | (reference : Sql.reference) :: rest ->
        let%bind column = resolve reference in
        let name = I.to_string (S.column_name column) in
        if List.mem seen name ~equal:String.equal then
          fail reference.offset ("duplicate target column: " ^ name)
        else
          loop (name :: seen) rest
    in
    loop [] references
  in
  let bind_parameter reference value =
    let%bind column = resolve reference in
    let%map codec = codec ~offset:reference.offset column in
    { value; codec }
  in
  let conditions ~excluded values =
    List.map values ~f:(fun ((reference : Sql.reference), value) ->
      let%bind column =
        match reference.names with
        | "excluded" :: _ when excluded -> resolve_excluded reference
        | _ -> resolve reference
      in
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
  let write (reference : Sql.reference) value =
    let%bind column = resolve reference in
    match value with
    | Sql.Default _ -> Ok []
    | Bind value ->
      let%map parameter = bind_parameter reference value in
      [ parameter ]
    | Excluded source ->
      let%bind source_column = resolve_excluded source in
      let%bind _ = codec ~offset:source.offset source_column in
      let%bind _ = codec ~offset:reference.offset column in
      (match S.column_postgresql_type column, S.column_postgresql_type source_column with
       | Some (schema, name), Some (source_schema, source_name)
         when String.equal (I.to_string schema) (I.to_string source_schema)
              && String.equal (I.to_string name) (I.to_string source_name) -> Ok []
       | _ ->
         fail
           source.offset
           "EXCLUDED assignment requires identical native types; implicit casts are unsupported")
  in
  let assignments values =
    let%bind () = unique_columns (List.map values ~f:fst) in
    List.map values ~f:(fun (reference, value) -> write reference value)
    |> Result.all
    |> Result.map ~f:List.concat
  in
  let conflict (conflict : Sql.conflict) =
    let%bind () =
      match conflict.target with
      | None ->
        (match conflict.action with
         | Do_nothing -> Ok ()
         | Do_update _ -> fail 0 "ON CONFLICT DO UPDATE requires conflict columns")
      | Some [] -> fail 0 "conflict target requires at least one column"
      | Some references ->
        let%bind () = unique_columns references in
        let names =
          List.concat_map references ~f:(fun reference -> reference.Sql.names)
        in
        let keys =
          List.map (S.unique_constraints table) ~f:(fun key ->
            List.map (S.unique_constraint_columns key) ~f:I.to_string)
        in
        let primary =
          List.filter (S.columns table) ~f:(fun column ->
            Option.is_some (S.column_primary_key_position column))
          |> List.map ~f:(fun column -> I.to_string (S.column_name column))
        in
        let sorted = List.sort ~compare:String.compare names in
        if
          List.exists (primary :: keys) ~f:(fun key ->
            List.equal String.equal sorted (List.sort ~compare:String.compare key))
        then
          Ok ()
        else
          fail
            (List.hd_exn references).offset
            "conflict columns do not match a primary or unique key in the snapshot"
    in
    match conflict.action with
    | Do_nothing -> Ok []
    | Do_update (values, predicates) ->
      let%bind () =
        if String.equal (Option.value query.alias ~default:query.table) "excluded" then
          fail 0 "ON CONFLICT DO UPDATE requires a target alias other than excluded"
        else
          Ok ()
      in
      let%bind writes = assignments values in
      let%map predicates = conditions ~excluded:true predicates in
      writes @ predicates
  in
  let%bind writes =
    match query.statement with
    | Select | Delete -> Ok []
    | Update values -> assignments values
    | Insert { columns; rows; conflict = on_conflict } ->
      let%bind () = unique_columns columns in
      let%bind parameters =
        match rows with
        | None -> Ok []
        | Some rows ->
          let%bind () =
            if List.is_empty columns then
              fail 0 "INSERT VALUES requires explicit target columns"
            else
              Ok ()
          in
          List.map rows ~f:(fun row ->
            match List.zip columns row with
            | Unequal_lengths ->
              let offset =
                match row with
                | [] -> 0
                | Sql.Bind parameter :: _ -> parameter.start
                | Default offset :: _ -> offset
                | Excluded reference :: _ -> reference.offset
              in
              fail offset "VALUES row length does not match INSERT columns"
            | Ok values ->
              List.map values ~f:(fun (column, value) -> write column value)
              |> Result.all
              |> Result.map ~f:List.concat)
          |> Result.all
          |> Result.map ~f:List.concat
      in
      let%map extra =
        match on_conflict with
        | None -> Ok []
        | Some value -> conflict value
      in
      parameters @ extra
  in
  let%bind predicates = conditions ~excluded:false query.conditions in
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
  let%bind result =
    if not (List.is_empty fields) then
      Ok (Rows fields)
    else if not (List.is_empty query.projection) then
      fail 0 "projection must return at least one column"
    else (
      match
        query.statement
      with
      | Select -> fail 0 "SELECT must return at least one column"
      | Insert _ | Update _ | Delete -> Ok Command)
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
  let parameters =
    List.sort (writes @ predicates) ~compare:(fun left right ->
      Int.compare left.value.start right.value.start)
  in
  let pieces, stop =
    List.foldi parameters ~init:([], 0) ~f:(fun index (pieces, stop) { value; _ } ->
      let text = String.sub query.source ~pos:stop ~len:(value.start - stop) in
      ("$" ^ Int.to_string (index + 1)) :: text :: pieces, value.stop)
  in
  let tail = String.sub query.source ~pos:stop ~len:(String.length query.source - stop) in
  let sql = String.concat (List.rev (tail :: pieces)) in
  Ok { sql; result; parameters }
;;
