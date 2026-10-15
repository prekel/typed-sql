open! Base
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

type field =
  { name : string
  ; codec : Codec.t
  ; nullable : bool
  }

type parameter = Predicate_plan.parameter =
  { value : Sql.parameter
  ; codec : Codec.t
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
  Result.map (Native_type.of_column ~offset column) ~f:Native_type.codec
;;

let create_legacy schema (query : Sql.t) =
  let open Result.Let_syntax in
  let find_table (relation : Sql.relation) =
    match
      List.filter (S.tables schema) ~f:(fun table ->
        String.equal relation.table (I.to_string (S.table_name table))
        && Option.value_map (S.table_schema table) ~default:false ~f:(fun schema ->
          String.equal relation.schema (I.to_string schema)))
    with
    | [ table ] -> Ok table
    | [] ->
      fail relation.offset ("unknown table: " ^ relation.schema ^ "." ^ relation.table)
    | _ ->
      fail
        relation.offset
        ("ambiguous table in snapshot: " ^ relation.schema ^ "." ^ relation.table)
  in
  let primary : Sql.relation =
    { schema = query.schema; table = query.table; alias = query.alias; offset = 0 }
  in
  let%bind table = find_table primary in
  let qualifier sources (reference : Sql.reference) names =
    let matches (relation : Sql.relation) =
      match names with
      | [] -> true
      | [ name ] ->
        String.equal name (Option.value relation.alias ~default:relation.table)
      | [ schema; name ] ->
        Option.is_none relation.alias
        && String.equal schema relation.schema
        && String.equal name relation.table
      | _ -> false
    in
    let matches = List.filter sources ~f:(fun (relation, _) -> matches relation) in
    match names, matches with
    | [], _ | _, [ _ ] -> Ok matches
    | _, [] -> fail reference.offset "column qualifier does not name the statement source"
    | _ -> fail reference.offset "ambiguous table qualifier"
  in
  let resolve_in sources (reference : Sql.reference) =
    match List.rev reference.names with
    | [] -> fail reference.offset "expected column name"
    | name :: reversed_qualifier ->
      let%bind sources = qualifier sources reference (List.rev reversed_qualifier) in
      let columns =
        List.concat_map sources ~f:(fun (_, table) ->
          List.filter (S.columns table) ~f:(fun column ->
            String.equal name (I.to_string (S.column_name column))))
      in
      (match columns with
       | [ column ] -> Ok column
       | [] -> fail reference.offset ("unknown column: " ^ name)
       | _ -> fail reference.offset ("ambiguous column: " ^ name))
  in
  let%bind sources, join_parameters =
    List.fold
      query.joins
      ~init:(Ok ([ primary, table ], []))
      ~f:(fun state join ->
        let%bind sources, parameters = state in
        let relation = join.Sql.relation in
        let exposed (source : Sql.relation) =
          Option.value source.alias ~default:source.table
        in
        let duplicate =
          List.exists sources ~f:(fun (previous, _) ->
            String.equal (exposed previous) (exposed relation)
            && (Option.is_some previous.alias
                || Option.is_some relation.alias
                || (String.equal previous.schema relation.schema
                    && String.equal previous.table relation.table)))
        in
        let%bind () =
          if duplicate then
            fail relation.offset ("duplicate source name: " ^ exposed relation)
          else
            Ok ()
        in
        let%bind table = find_table relation in
        let sources = sources @ [ relation, table ] in
        let%map added =
          Predicate_plan.create ~resolve:(resolve_in sources) (Some join.condition)
        in
        sources, parameters @ added)
  in
  let resolve = resolve_in sources in
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
    Predicate_plan.create
      ~resolve:(fun (reference : Sql.reference) ->
        match reference.names with
        | "excluded" :: _ when excluded -> resolve_excluded reference
        | _ -> resolve reference)
      values
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
    let%bind () =
      match
        ( S.column_postgresql_type_info column
        , S.column_postgresql_attribute_not_null column )
      with
      | Some { kind = Native_domain _; _ }, None ->
        fail
          offset
          "missing PostgreSQL attribute nullability for domain column; refresh the schema snapshot"
      | _ -> Ok ()
    in
    let%map codec = codec ~offset column in
    { name = Option.value name ~default:(I.to_string (S.column_name column))
    ; codec
    ; nullable =
        Option.value_map
          (S.column_postgresql_attribute_not_null column)
          ~default:(S.column_nullable column)
          ~f:not
    }
  in
  let%bind fields =
    List.map query.projection ~f:(function
      | Sql.Column (reference, name) ->
        let%bind column = resolve reference in
        let%map field = field ~offset:reference.offset ?name column in
        [ field ]
      | All reference ->
        let%bind selected = qualifier sources reference reference.names in
        List.concat_map selected ~f:(fun (_, table) -> S.columns table)
        |> List.map ~f:(field ~offset:reference.offset)
        |> Result.all)
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
      let%bind native = Native_type.of_column ~offset:reference.offset column in
      if Native_type.comparable native then
        Ok ()
      else
        fail reference.offset "PostgreSQL json has no ordering operator; use jsonb")
    |> Result.all
    |> Result.map ~f:(fun _ -> ())
  in
  let%bind pagination =
    List.map
      (Option.to_list query.limit @ Option.to_list query.offset)
      ~f:(function
        | Sql.Parameter_value value -> Ok [ { value; codec = Codec.Scalar "int64" } ]
        | _ -> Ok [])
    |> Result.all
    |> Result.map ~f:List.concat
  in
  let parameters =
    List.sort
      (writes @ join_parameters @ predicates @ pagination)
      ~compare:(fun left right -> Int.compare left.value.start right.value.start)
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

let create schema (query : Sql.t) =
  match query.extended with
  | None -> create_legacy schema query
  | Some statement ->
    let open Result.Let_syntax in
    let%map result = Query_plan.create schema statement in
    let parameters =
      List.map result.parameters ~f:(fun (parameter : Query_plan.parameter) ->
        { value = parameter.value; codec = parameter.codec })
    in
    let pieces, stop =
      List.foldi parameters ~init:([], 0) ~f:(fun index (pieces, stop) { value; _ } ->
        let text = String.sub query.source ~pos:stop ~len:(value.start - stop) in
        ("$" ^ Int.to_string (index + 1)) :: text :: pieces, value.stop)
    in
    let tail =
      String.sub query.source ~pos:stop ~len:(String.length query.source - stop)
    in
    let sql = String.concat (List.rev (tail :: pieces)) in
    let fields =
      List.map result.fields ~f:(fun (field : Query_plan.field) ->
        { name = field.name; codec = field.codec; nullable = field.nullable })
    in
    { sql
    ; parameters
    ; result =
        (if List.is_empty fields then
           Command
         else
           Rows fields)
    }
;;
