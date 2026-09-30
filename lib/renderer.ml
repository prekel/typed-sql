open! Base

type state =
  { dialect : Dialect.t
  ; next_parameter : int
  ; parameters_rev : Ast.parameter list
  ; slot_indices : (int * int) list
  ; next_cte : int
  ; cte_names : (int * string) list
  }

let initial_state =
  { dialect = Dialect.Postgresql
  ; next_parameter = 0
  ; parameters_rev = []
  ; slot_indices = []
  ; next_cte = 0
  ; cte_names = []
  }
;;

let initial_state_for dialect = { initial_state with dialect }
let text value = Template.Text value
let break flat = Template.Break flat
let concat templates = Template.concat templates
let nest template = Template.Nest template
let separate templates ~by = List.intersperse templates ~sep:by |> concat

let rec select_query_output_field_names = function
  | Ast.Simple select ->
    List.map select.Ast.projection ~f:(function
      | Ast.Column { name; _ } -> Some name
      | _ -> None)
  | Ast.Source_free _ -> [ None ]
  | Ast.Compound compound -> select_query_output_field_names compound.left
;;

let quote_identifier identifier =
  let value = Identifier.to_string identifier in
  let escaped = String.substr_replace_all value ~pattern:"\"" ~with_:"\"\"" in
  concat [ text "\""; text escaped; text "\"" ]
;;

let render_table_source source =
  let table = quote_identifier source.Ast.table in
  match source.schema with
  | None -> table
  | Some schema -> concat [ quote_identifier schema; text "."; table ]
;;

let alias_for aliases source_id = List.Assoc.find_exn aliases source_id ~equal:Int.equal
let cte_name state id = List.Assoc.find_exn state.cte_names id ~equal:Int.equal

let arithmetic_sql = function
  | Ast.Add -> " + "
  | Ast.Subtract -> " - "
  | Ast.Multiply -> " * "
  | Ast.Divide -> " / "
;;

let string_function_sql = function
  | Ast.Lower -> "LOWER"
  | Ast.Upper -> "UPPER"
  | Ast.Length -> "CHAR_LENGTH"
  | Ast.Sqlite_length -> "LENGTH"
;;

let comparison_sql = function
  | Ast.Eq -> " = "
  | Ast.Neq -> " <> "
  | Ast.Lt -> " < "
  | Ast.Lte -> " <= "
  | Ast.Gt -> " > "
  | Ast.Gte -> " >= "
  | Ast.Like -> " LIKE "
  | Ast.Is_distinct_from -> " IS DISTINCT FROM "
  | Ast.Sqlite_is_not -> " IS NOT "
;;

let aliases_for_select ~parent_aliases (select : Ast.select) =
  let sources =
    select.Ast.source :: List.map select.joins ~f:(fun (join : Ast.join) -> join.source)
  in
  let first_index = List.length parent_aliases in
  List.append
    parent_aliases
    (List.mapi sources ~f:(fun index source ->
       source.source_id, Stdlib.Format.asprintf "t%d" (first_index + index)))
;;

let render_parameter parameter state =
  match parameter with
  | Ast.Value _ ->
    let index = state.next_parameter in
    ( Template.Param index
    , { state with
        next_parameter = index + 1
      ; parameters_rev = parameter :: state.parameters_rev
      } )
  | Ast.Slot { id; _ } ->
    (match List.Assoc.find state.slot_indices id ~equal:Int.equal with
     | Some index -> Template.Param index, state
     | None ->
       let index = state.next_parameter in
       ( Template.Param index
       , { next_parameter = index + 1
         ; dialect = state.dialect
         ; parameters_rev = parameter :: state.parameters_rev
         ; slot_indices = (id, index) :: state.slot_indices
         ; next_cte = state.next_cte
         ; cte_names = state.cte_names
         } ))
;;

let rec postgresql_type_name : type a. a Db_type.t -> string =
  fun db_type ->
  match Db_type.view db_type with
  | Bool -> "boolean"
  | Int -> "integer"
  | Int64 -> "bigint"
  | Float -> "double precision"
  | Numeric -> "numeric"
  | Text -> "text"
  | Bytes -> "bytea"
  | Date -> "date"
  | Timestamp -> "timestamp with time zone"
  | Uuid -> "uuid"
  | Option inner -> postgresql_type_name inner
  | Map { repr; _ } -> postgresql_type_name repr
;;

let parameter_type_name = function
  | Ast.Value (Db_type.Value (db_type, _)) -> postgresql_type_name db_type
  | Ast.Slot { db_type = Db_type.Pack db_type; _ } -> postgresql_type_name db_type
;;

let rec render_expr ~aliases expression state =
  match expression with
  | Ast.Column { source_id; name; _ } ->
    let alias = alias_for aliases source_id in
    let column = quote_identifier name in
    ( (if String.is_empty alias then
         column
       else
         concat [ text alias; text "."; column ])
    , state )
  | Ast.Param parameter -> render_parameter parameter state
  | Ast.Arithmetic (operator, left, right) ->
    let left, state = render_expr ~aliases left state in
    let right, state = render_expr ~aliases right state in
    concat [ text "("; left; text (arithmetic_sql operator); right; text ")" ], state
  | Ast.String_function (function_, expression) ->
    let expression, state = render_expr ~aliases expression state in
    concat [ text (string_function_sql function_); text "("; expression; text ")" ], state
  | Ast.Concat (left, right) ->
    let left, state = render_expr ~aliases left state in
    let right, state = render_expr ~aliases right state in
    concat [ text "("; left; text " || "; right; text ")" ], state
  | Ast.Coalesce (nullable, default) ->
    let nullable, state = render_expr ~aliases nullable state in
    let default, state = render_expr ~aliases default state in
    concat [ text "COALESCE("; nullable; text ", "; default; text ")" ], state
  | Ast.Case (branches, else_) ->
    let branches, state = render_case_branches ~aliases branches state in
    let else_, state = render_expr ~aliases else_ state in
    ( concat
        [ text "(CASE"
        ; nest (concat [ break " "; branches; break " "; text "ELSE "; else_ ])
        ; break " "
        ; text "END)"
        ]
    , state )
  | Ast.Aggregate Ast.Count_all -> text "COUNT(*)", state
  | Ast.Aggregate (Ast.Count expression) ->
    let expression, state = render_expr ~aliases expression state in
    concat [ text "COUNT("; expression; text ")" ], state
  | Ast.Aggregate (Ast.Count_distinct expression) ->
    let expression, state = render_expr ~aliases expression state in
    concat [ text "COUNT(DISTINCT "; expression; text ")" ], state
  | Ast.Aggregate
      ( Ast.Sum_int expression
      | Ast.Sum_float expression
      | Ast.Sum_int64 expression
      | Ast.Sum_numeric expression ) ->
    let expression, state = render_expr ~aliases expression state in
    concat [ text "SUM("; expression; text ")" ], state
  | Ast.Aggregate (Ast.Min expression) ->
    let expression, state = render_expr ~aliases expression state in
    concat [ text "MIN("; expression; text ")" ], state
  | Ast.Aggregate (Ast.Max expression) ->
    let expression, state = render_expr ~aliases expression state in
    concat [ text "MAX("; expression; text ")" ], state
  | Ast.Aggregate (Ast.Multiset_agg multiset) ->
    let multiset, state = render_multiset_aggregate_raw ~aliases multiset state in
    render_multiset_output multiset state
  | Ast.Scalar_subquery select ->
    let select, state = render_select ~parent_aliases:aliases select state in
    concat [ text "("; nest (concat [ break ""; select ]); break ""; text ")" ], state
  | Ast.Multiset_subquery multiset ->
    let multiset, state = render_multiset_subquery_raw ~aliases multiset state in
    render_multiset_output multiset state
  | Ast.Exists_expr select -> render_exists ~aliases ~operator:"EXISTS" select state
  | Ast.Current_timestamp -> text "CURRENT_TIMESTAMP", state

and render_multiset_output multiset state =
  match state.dialect with
  | Dialect.Postgresql ->
    ( concat
        [ text "CAST("
        ; nest (concat [ break ""; multiset; break " "; text "AS TEXT" ])
        ; break ""
        ; text ")"
        ]
    , state )
  | Dialect.Sqlite -> multiset, state

and render_json_value ~aliases expression state =
  match expression with
  | Ast.Aggregate (Ast.Multiset_agg multiset) ->
    let multiset, state = render_multiset_aggregate_raw ~aliases multiset state in
    render_nested_json multiset state
  | Ast.Multiset_subquery multiset ->
    let multiset, state = render_multiset_subquery_raw ~aliases multiset state in
    render_nested_json multiset state
  | _ -> render_expr ~aliases expression state

and render_nested_json multiset state =
  match state.dialect with
  | Dialect.Postgresql -> multiset, state
  | Dialect.Sqlite -> concat [ text "JSON("; multiset; text ")" ], state

and render_json_values ~aliases ~separator expressions state =
  match expressions with
  | [] -> Template.Empty, state
  | [ expression ] -> render_json_value ~aliases expression state
  | expression :: rest ->
    let expression, state = render_json_value ~aliases expression state in
    let rest, state = render_json_values ~aliases ~separator rest state in
    concat [ expression; separator; rest ], state

and render_json_row ~aliases expressions state =
  let multiple = Int.(List.length expressions > 1) in
  let values, state =
    render_json_values
      ~aliases
      ~separator:(concat [ text ","; break " " ])
      expressions
      state
  in
  let function_ =
    match state.dialect with
    | Dialect.Postgresql -> "JSONB_BUILD_ARRAY"
    | Dialect.Sqlite -> "JSON_ARRAY"
  in
  let arguments =
    if multiple then
      concat [ text "("; nest (concat [ break ""; values ]); break ""; text ")" ]
    else
      concat [ text "("; values; text ")" ]
  in
  concat [ text function_; arguments ], state

and render_multiset_aggregate_raw ~aliases multiset state =
  let row, state = render_json_row ~aliases multiset.Ast.fields state in
  let order_by, state = render_order_by ~aliases multiset.order_by state in
  let filter, state =
    match multiset.filter with
    | None -> Template.Empty, state
    | Some condition ->
      let condition, state = render_condition ~aliases condition state in
      ( concat
          [ text " FILTER ("
          ; nest (concat [ break ""; text "WHERE "; condition ])
          ; break ""
          ; text ")"
          ]
      , state )
  in
  let aggregate, empty =
    match state.dialect with
    | Dialect.Postgresql -> "JSONB_AGG", "JSONB_BUILD_ARRAY()"
    | Dialect.Sqlite -> "JSON_GROUP_ARRAY", "JSON_ARRAY()"
  in
  let order_by =
    match multiset.order_by with
    | [] -> Template.Empty
    | _ -> concat [ break " "; text "ORDER BY "; order_by ]
  in
  let aggregate_call =
    concat
      [ text aggregate
      ; text "("
      ; nest (concat [ break ""; row; order_by ])
      ; break ""
      ; text ")"
      ; filter
      ]
  in
  ( concat
      [ text "COALESCE("
      ; nest (concat [ break ""; aggregate_call; text ","; break " "; text empty ])
      ; break ""
      ; text ")"
      ]
  , state )

and render_multiset_columns alias names types state =
  let columns = List.zip_exn names types in
  let render (name, Db_type.Pack db_type) =
    let column = concat [ text alias; text "."; quote_identifier name ] in
    match state.dialect with
    | Dialect.Sqlite when Db_type.is_json_result db_type ->
      concat [ text "JSON("; column; text ")" ]
    | Dialect.Sqlite | Dialect.Postgresql -> column
  in
  List.map columns ~f:render |> separate ~by:(concat [ text ","; break " " ])

and render_multiset_subquery_raw ~aliases multiset state =
  let names =
    List.mapi multiset.Ast.field_types ~f:(fun index _ ->
      Identifier.of_string_exn ("v" ^ Int.to_string index))
  in
  let query, state =
    render_select_query
      ~json_projection:true
      ~parent_aliases:aliases
      ~output_names:names
      multiset.query
      state
  in
  let alias = "m0" in
  let fields = render_multiset_columns alias names multiset.field_types state in
  let row_function, aggregate, empty =
    match state.dialect with
    | Dialect.Postgresql -> "JSONB_BUILD_ARRAY", "JSONB_AGG", "JSONB_BUILD_ARRAY()"
    | Dialect.Sqlite -> "JSON_ARRAY", "JSON_GROUP_ARRAY", "JSON_ARRAY()"
  in
  let lateral =
    match state.dialect with
    | Dialect.Postgresql -> text "LATERAL "
    | Dialect.Sqlite -> Template.Empty
  in
  let row =
    concat
      [ text row_function
      ; text "("
      ; nest (concat [ break ""; fields ])
      ; break ""
      ; text ")"
      ]
  in
  let aggregate_call =
    concat
      [ text aggregate; text "("; nest (concat [ break ""; row ]); break ""; text ")" ]
  in
  let coalesce =
    concat
      [ text "COALESCE("
      ; nest (concat [ break ""; aggregate_call; text ","; break " "; text empty ])
      ; break ""
      ; text ")"
      ]
  in
  ( concat
      [ text "("
      ; nest
          (concat
             [ break ""
             ; text "SELECT"
             ; nest (concat [ break " "; coalesce ])
             ; break " "
             ; text "FROM "
             ; lateral
             ; text "("
             ; nest (concat [ break ""; query ])
             ; break ""
             ; text ") AS "
             ; text alias
             ])
      ; break ""
      ; text ")"
      ]
  , state )

and render_case_branches ~aliases branches state =
  match branches with
  | [] -> Template.Empty, state
  | (condition, expression) :: rest ->
    let condition, state = render_condition ~aliases condition state in
    let expression, state = render_expr ~aliases expression state in
    let rendered_rest, state = render_case_branches ~aliases rest state in
    let rendered_rest =
      match rest with
      | [] -> Template.Empty
      | _ -> concat [ break " "; rendered_rest ]
    in
    concat [ text "WHEN "; condition; text " THEN "; expression; rendered_rest ], state

and render_condition ~aliases condition state =
  match condition with
  | Ast.True -> text "TRUE", state
  | Ast.False -> text "FALSE", state
  | Ast.Compare (comparison, left, right) ->
    let left, state = render_expr ~aliases left state in
    let right, state = render_expr ~aliases right state in
    concat [ text "("; left; text (comparison_sql comparison); right; text ")" ], state
  | Ast.Is_null expression ->
    let expression, state = render_null_operand ~aliases expression state in
    concat [ text "("; expression; text " IS NULL)" ], state
  | Ast.Is_not_null expression ->
    let expression, state = render_null_operand ~aliases expression state in
    concat [ text "("; expression; text " IS NOT NULL)" ], state
  | Ast.In (expression, values) ->
    render_membership ~aliases ~operator:" IN " expression values state
  | Ast.Not_in (expression, values) ->
    render_membership ~aliases ~operator:" NOT IN " expression values state
  | Ast.Between (expression, lower, upper) ->
    let expression, state = render_expr ~aliases expression state in
    let lower, state = render_expr ~aliases lower state in
    let upper, state = render_expr ~aliases upper state in
    ( concat
        [ text "("; expression; text " BETWEEN "; lower; text " AND "; upper; text ")" ]
    , state )
  | Ast.Exists select -> render_exists ~aliases ~operator:"EXISTS" select state
  | Ast.Not_exists select -> render_exists ~aliases ~operator:"NOT EXISTS" select state
  | Ast.In_subquery (expression, select) ->
    render_subquery_membership ~aliases ~operator:" IN " expression select state
  | Ast.Not_in_subquery (expression, select) ->
    render_subquery_membership ~aliases ~operator:" NOT IN " expression select state
  | Ast.Not condition ->
    let condition, state = render_condition ~aliases condition state in
    concat [ text "(NOT "; condition; text ")" ], state
  | Ast.And conditions -> render_condition_list ~aliases ~operator:"AND" conditions state
  | Ast.Or conditions -> render_condition_list ~aliases ~operator:"OR" conditions state

and render_null_operand ~aliases expression state =
  let rendered, state = render_expr ~aliases expression state in
  match state.dialect, expression with
  | Dialect.Postgresql, Ast.Param parameter ->
    ( concat
        [ text "CAST("
        ; rendered
        ; text " AS "
        ; text (parameter_type_name parameter)
        ; text ")"
        ]
    , state )
  | Dialect.Postgresql, _ | Dialect.Sqlite, _ -> rendered, state

and render_condition_list ~aliases ~operator conditions state =
  match conditions with
  | [] -> text "()", state
  | [ condition ] ->
    let condition, state = render_condition ~aliases condition state in
    concat [ text "("; condition; text ")" ], state
  | conditions ->
    let conditions, state = render_conditions ~aliases ~operator conditions state in
    concat [ text "("; nest (concat [ break ""; conditions ]); break ""; text ")" ], state

and render_conditions ~aliases ~operator conditions state =
  match conditions with
  | [] -> Template.Empty, state
  | [ condition ] -> render_condition ~aliases condition state
  | condition :: rest ->
    let condition, state = render_condition ~aliases condition state in
    let rest, state = render_conditions ~aliases ~operator rest state in
    concat [ condition; break " "; text operator; text " "; rest ], state

and render_membership ~aliases ~operator expression values state =
  let multiline = List.length values > 1 in
  let expression, state = render_expr ~aliases expression state in
  let values, state =
    render_expressions ~aliases ~separator:(concat [ text ","; break " " ]) values state
  in
  let values =
    if multiline then
      concat [ nest (concat [ break ""; values ]); break "" ]
    else
      values
  in
  concat [ text "("; expression; text operator; text "("; values; text "))" ], state

and render_exists ~aliases ~operator select state =
  let select, state = render_select ~parent_aliases:aliases select state in
  ( concat
      [ text "("
      ; text operator
      ; text " ("
      ; nest (concat [ break ""; select ])
      ; break ""
      ; text "))"
      ]
  , state )

and render_subquery_membership ~aliases ~operator expression select state =
  let expression, state = render_expr ~aliases expression state in
  let select, state = render_select ~parent_aliases:aliases select state in
  ( concat
      [ text "("
      ; expression
      ; text operator
      ; text "("
      ; nest (concat [ break ""; select ])
      ; break ""
      ; text "))"
      ]
  , state )

and render_expressions ~aliases ~separator expressions state =
  match expressions with
  | [] -> Template.Empty, state
  | [ expression ] -> render_expr ~aliases expression state
  | expression :: rest ->
    let expression, state = render_expr ~aliases expression state in
    let rest, state = render_expressions ~aliases ~separator rest state in
    concat [ expression; separator; rest ], state

and relation_column_names (relation : Ast.relation) =
  List.map relation.Ast.columns ~f:(function
    | Ast.Column { name; _ } -> name
    | _ -> assert false)

and render_values_rows ~aliases rows state =
  let rows_rev, state =
    List.fold rows ~init:([], state) ~f:(fun (rows_rev, state) row ->
      let expressions, state =
        render_expressions
          ~aliases
          ~separator:(concat [ text ","; break " " ])
          row.Ast.expressions
          state
      in
      let rendered =
        concat [ text "("; nest (concat [ break ""; expressions ]); break ""; text ")" ]
      in
      rendered :: rows_rev, state)
  in
  separate (List.rev rows_rev) ~by:(concat [ text ","; break " " ]), state

and render_values_source ~aliases (values : Ast.values) state =
  let columns =
    List.mapi values.columns ~f:(fun index -> function
      | Ast.Column { name; _ } ->
        concat
          [ text "\"v\"."
          ; quote_identifier
              (Identifier.of_string_exn ("column" ^ Int.to_string (index + 1)))
          ; text " AS "
          ; quote_identifier name
          ]
      | _ -> assert false)
    |> separate ~by:(concat [ text ","; break " " ])
  in
  let rows, state = render_values_rows ~aliases values.rows state in
  ( concat
      [ text "(SELECT"
      ; nest (concat [ break " "; columns ])
      ; break " "
      ; text "FROM (VALUES"
      ; nest (concat [ break " "; rows ])
      ; break " "
      ; text ") AS \"v\")"
      ]
  , state )

and render_source ?(lateral = false) ~aliases (source : Ast.source) state =
  match source.kind with
  | Ast.Table table -> render_table_source table, state
  | Ast.Cte id -> quote_identifier (Identifier.of_string_exn (cte_name state id)), state
  | Ast.Values values -> render_values_source ~aliases values state
  | Ast.Derived relation ->
    let query, state =
      render_select_query
        ~json_projection:lateral
        ~parent_aliases:aliases
        ~output_names:(relation_column_names relation)
        relation.query
        state
    in
    let lateral =
      match lateral, state.dialect with
      | true, Dialect.Postgresql -> text "LATERAL "
      | false, _ | true, Dialect.Sqlite -> Template.Empty
    in
    ( concat [ lateral; text "("; nest (concat [ break ""; query ]); break ""; text ")" ]
    , state )

and render_join ?(lateral = false) ~aliases (join : Ast.join) state =
  let kind =
    match join.Ast.kind with
    | Ast.Inner -> text "INNER JOIN "
    | Ast.Left -> text "LEFT JOIN "
  in
  let alias = alias_for aliases join.source.source_id in
  let source, state = render_source ~lateral ~aliases join.source state in
  let on, state = render_condition ~aliases join.on state in
  ( concat
      [ break " "
      ; kind
      ; source
      ; text " AS "
      ; text alias
      ; nest (concat [ break " "; text "ON "; on ])
      ]
  , state )

and render_joins ?(lateral = false) ~aliases joins state =
  match joins with
  | [] -> Template.Empty, state
  | join :: rest ->
    let join, state = render_join ~lateral ~aliases join state in
    let rest, state = render_joins ~lateral ~aliases rest state in
    concat [ join; rest ], state

and render_order_by ~aliases orders state =
  match orders with
  | [] -> Template.Empty, state
  | order :: rest ->
    let expression, state = render_expr ~aliases order.Ast.expr state in
    let direction =
      match order.direction with
      | Ast.Asc -> text " ASC"
      | Ast.Desc -> text " DESC"
    in
    let current = concat [ expression; direction ] in
    (match rest with
     | [] -> current, state
     | _ ->
       let rest, state = render_order_by ~aliases rest state in
       concat [ current; text ","; break " "; rest ], state)

and render_projection_expression ~aliases ~json_projection expression state =
  if json_projection then
    render_json_value ~aliases expression state
  else
    render_expr ~aliases expression state

and render_projection ~aliases ~json_projection ~output_names expressions state =
  match output_names with
  | [] ->
    let rec loop expressions state =
      match expressions with
      | [] -> Template.Empty, state
      | [ expression ] ->
        render_projection_expression ~aliases ~json_projection expression state
      | expression :: rest ->
        let expression, state =
          render_projection_expression ~aliases ~json_projection expression state
        in
        let rest, state = loop rest state in
        concat [ expression; text ","; break " "; rest ], state
    in
    loop expressions state
  | names ->
    let pairs = List.zip_exn expressions names in
    let rec loop pairs state =
      match pairs with
      | [] -> Template.Empty, state
      | [ (expression, name) ] ->
        let expression, state =
          render_projection_expression ~aliases ~json_projection expression state
        in
        concat [ expression; text " AS "; quote_identifier name ], state
      | (expression, name) :: rest ->
        let expression, state =
          render_projection_expression ~aliases ~json_projection expression state
        in
        let rest, state = loop rest state in
        ( concat
            [ expression; text " AS "; quote_identifier name; text ","; break " "; rest ]
        , state )
    in
    loop pairs state

and render_select
      ?(json_projection = false)
      ?(output_names = [])
      ?(sqlite_insert_upsert = false)
      ~parent_aliases
      (select : Ast.select)
      state
  =
  let render_body state =
    let aliases = aliases_for_select ~parent_aliases select in
    let projection, state =
      match select.Ast.projection with
      | [] -> text "1", state
      | projection ->
        render_projection ~aliases ~json_projection ~output_names projection state
    in
    let root_alias = alias_for aliases select.source.source_id in
    let root_source, state =
      render_source ~lateral:json_projection ~aliases select.source state
    in
    let joins, state =
      render_joins ~lateral:json_projection ~aliases select.joins state
    in
    let select_keyword =
      if select.distinct then
        text "SELECT DISTINCT"
      else
        text "SELECT"
    in
    let parts =
      concat
        [ select_keyword
        ; nest (concat [ break " "; projection ])
        ; break " "
        ; text "FROM "
        ; root_source
        ; text " AS "
        ; text root_alias
        ; joins
        ]
    in
    let parts, state =
      match select.where_ with
      | None when sqlite_insert_upsert ->
        concat [ parts; break " "; text "WHERE TRUE" ], state
      | None -> parts, state
      | Some condition ->
        let condition, state = render_condition ~aliases condition state in
        ( concat [ parts; break " "; text "WHERE"; nest (concat [ break " "; condition ]) ]
        , state )
    in
    let parts, state =
      match select.group_by with
      | [] -> parts, state
      | expressions ->
        let expressions, state =
          render_expressions
            ~aliases
            ~separator:(concat [ text ","; break " " ])
            expressions
            state
        in
        ( concat
            [ parts
            ; break " "
            ; text "GROUP BY"
            ; nest (concat [ break " "; expressions ])
            ]
        , state )
    in
    let parts, state =
      match select.having with
      | None -> parts, state
      | Some condition ->
        let condition, state = render_condition ~aliases condition state in
        ( concat
            [ parts; break " "; text "HAVING"; nest (concat [ break " "; condition ]) ]
        , state )
    in
    let parts, state =
      match select.order_by with
      | [] -> parts, state
      | orders ->
        let orders, state = render_order_by ~aliases orders state in
        ( concat [ parts; break " "; text "ORDER BY"; nest (concat [ break " "; orders ]) ]
        , state )
    in
    let render_offset parts state =
      match select.offset with
      | None -> parts, state
      | Some (Ast.Literal n) ->
        concat [ parts; break " "; text "OFFSET "; text (Int.to_string n) ], state
      | Some (Ast.Parameter parameter) ->
        let parameter, state = render_parameter parameter state in
        concat [ parts; break " "; text "OFFSET "; parameter ], state
    in
    let render_row_count prefix suffix parts state pagination =
      match pagination with
      | Ast.Literal n ->
        ( concat [ parts; break " "; text prefix; text (Int.to_string n); text suffix ]
        , state )
      | Ast.Parameter parameter ->
        let parameter, state = render_parameter parameter state in
        concat [ parts; break " "; text prefix; parameter; text suffix ], state
    in
    let parts, state =
      match select.limit with
      | None -> render_offset parts state
      | Some (Ast.Limit pagination) ->
        let parts, state = render_row_count "LIMIT " "" parts state pagination in
        render_offset parts state
      | Some (Ast.Fetch_with_ties pagination) ->
        let parts, state = render_offset parts state in
        render_row_count "FETCH FIRST " " ROWS WITH TIES" parts state pagination
    in
    match select.locking with
    | None -> parts, state
    | Some locking ->
      let targets =
        match locking.of_sources with
        | None -> Template.Empty
        | Some sources ->
          let aliases =
            List.map sources ~f:(fun source -> text (alias_for aliases source))
          in
          concat [ text " OF "; separate aliases ~by:(text ", ") ]
      in
      ( concat
          [ parts
          ; break " "
          ; text "FOR UPDATE"
          ; targets
          ; (if locking.skip_locked then
               text " SKIP LOCKED"
             else
               Template.Empty)
          ]
      , state )
  in
  render_with select.ctes ~render_body state

and set_operator = function
  | Ast.Union -> "UNION"
  | Ast.Union_all -> "UNION ALL"
  | Ast.Intersect -> "INTERSECT"
  | Ast.Intersect_all -> "INTERSECT ALL"
  | Ast.Except -> "EXCEPT"
  | Ast.Except_all -> "EXCEPT ALL"

and render_set_order_by ~output_names ~left orders =
  match orders with
  | [] -> Template.Empty
  | _ ->
    let orders =
      List.map orders ~f:(fun order ->
        let field =
          match output_names with
          | [] -> order.Ast.field
          | _ ->
            (match
               List.findi (select_query_output_field_names left) ~f:(fun _ -> function
                 | Some field -> Identifier.equal field order.field
                 | None -> false)
             with
             | Some (index, _) -> List.nth_exn output_names index
             | None -> order.field)
        in
        let direction =
          match order.Ast.direction with
          | Ast.Asc -> text " ASC"
          | Ast.Desc -> text " DESC"
        in
        concat [ quote_identifier field; direction ])
    in
    let orders = separate orders ~by:(concat [ text ","; break " " ]) in
    concat [ break " "; text "ORDER BY"; nest (concat [ break " "; orders ]) ]

and render_compound_branch
      ?(sqlite_insert_upsert = false)
      ~json_projection
      ~parent_aliases
      ~output_names
      query
      state
  =
  let query, state =
    render_select_query ~json_projection ~parent_aliases ~output_names query state
  in
  let lateral =
    match json_projection, state.dialect with
    | true, Dialect.Postgresql -> text "LATERAL "
    | false, _ | true, Dialect.Sqlite -> Template.Empty
  in
  let branch =
    concat
      [ text "SELECT *"
      ; break " "
      ; text "FROM "
      ; lateral
      ; text "("
      ; nest (concat [ break ""; query ])
      ; break ""
      ; text ") AS s0"
      ]
  in
  ( (if sqlite_insert_upsert then
       concat [ branch; break " "; text "WHERE TRUE" ]
     else
       branch)
  , state )

and render_select_query
      ?(json_projection = false)
      ?(output_names = [])
      ?(sqlite_insert_upsert = false)
      ~parent_aliases
      query
      state
  =
  match query with
  | Ast.Simple select ->
    render_select
      ~json_projection
      ~output_names
      ~sqlite_insert_upsert
      ~parent_aliases
      select
      state
  | Ast.Source_free source_free ->
    let render_body state =
      let projection, state =
        render_projection
          ~aliases:parent_aliases
          ~json_projection
          ~output_names
          [ source_free.expression ]
          state
      in
      let select = concat [ text "SELECT"; nest (concat [ break " "; projection ]) ] in
      ( (if sqlite_insert_upsert then
           concat [ select; break " "; text "WHERE TRUE" ]
         else
           select)
      , state )
    in
    render_with source_free.ctes ~render_body state
  | Ast.Compound compound ->
    let render_body state =
      let left, state =
        render_compound_branch
          ~json_projection
          ~parent_aliases
          ~output_names
          compound.left
          state
      in
      let right, state =
        render_compound_branch
          ~sqlite_insert_upsert
          ~json_projection
          ~parent_aliases
          ~output_names
          compound.right
          state
      in
      ( concat
          [ left
          ; break " "
          ; text (set_operator compound.operator)
          ; break " "
          ; right
          ; render_set_order_by ~output_names ~left:compound.left compound.order_by
          ]
      , state )
    in
    render_with compound.ctes ~render_body state

and cte_column_names (cte : Ast.cte) =
  List.map cte.Ast.columns ~f:(function
    | Ast.Column { name; _ } -> name
    | _ -> assert false)

and allocate_cte_names ctes state =
  List.fold ctes ~init:state ~f:(fun state (cte : Ast.cte) ->
    let name = "c" ^ Int.to_string state.next_cte in
    { state with
      next_cte = state.next_cte + 1
    ; cte_names = (cte.cte_id, name) :: state.cte_names
    })

and render_cte (cte : Ast.cte) state =
  let name = quote_identifier (Identifier.of_string_exn (cte_name state cte.cte_id)) in
  let columns =
    match cte_column_names cte with
    | [] -> Template.Empty
    | columns ->
      let columns =
        List.map columns ~f:quote_identifier
        |> separate ~by:(concat [ text ","; break " " ])
      in
      concat [ text " ("; nest (concat [ break ""; columns ]); break ""; text ")" ]
  in
  let materialization =
    match cte.materialization with
    | None -> Template.Empty
    | Some Ast.Materialized -> text " MATERIALIZED"
    | Some Ast.Not_materialized -> text " NOT MATERIALIZED"
  in
  let body, state =
    match cte.body with
    | Ast.Select_body query -> render_select_query ~parent_aliases:[] query state
    | Ast.Recursive_body { union; anchor; step } ->
      let anchor, state = render_select_query ~parent_aliases:[] anchor.query state in
      let step, state = render_select_query ~parent_aliases:[] step.query state in
      let union =
        match union with
        | Ast.Recursive_union -> "UNION"
        | Ast.Recursive_union_all -> "UNION ALL"
      in
      concat [ anchor; break " "; text union; break " "; step ], state
    | Ast.Returning_body returning -> render_returning returning state
    | Ast.Command_body command -> render_command_ast command state
  in
  ( concat
      [ name
      ; columns
      ; text " AS"
      ; materialization
      ; text " ("
      ; nest (concat [ break ""; body ])
      ; break ""
      ; text ")"
      ]
  , state )

and render_ctes ctes state =
  let recursive =
    List.exists ctes ~f:(fun (cte : Ast.cte) ->
      match cte.body with
      | Ast.Recursive_body _ -> true
      | Ast.Select_body _ | Ast.Returning_body _ | Ast.Command_body _ -> false)
  in
  let state = allocate_cte_names ctes state in
  let rec loop ctes state =
    match ctes with
    | [] -> Template.Empty, state
    | [ cte ] -> render_cte cte state
    | cte :: rest ->
      let cte, state = render_cte cte state in
      let rest, state = loop rest state in
      concat [ cte; text ","; break " "; rest ], state
  in
  let rendered_ctes, state = loop ctes state in
  let keyword =
    if recursive then
      text "WITH RECURSIVE"
    else
      text "WITH"
  in
  concat [ keyword; nest (concat [ break " "; rendered_ctes ]) ], state

and render_with ctes ~render_body state =
  match ctes with
  | [] -> render_body state
  | _ ->
    let rendered_ctes, state = render_ctes ctes state in
    let body, state = render_body state in
    concat [ rendered_ctes; break " "; body ], state

and render_assignment_value ~aliases value state =
  match value with
  | Ast.Expression expression -> render_expr ~aliases expression state
  | Ast.Default -> text "DEFAULT", state

and render_assignment ~aliases assignment state =
  let value, state = render_assignment_value ~aliases assignment.Ast.value state in
  concat [ quote_identifier assignment.column; text " = "; value ], state

and render_assignments ~aliases assignments state =
  match assignments with
  | [] -> Template.Empty, state
  | [ assignment ] -> render_assignment ~aliases assignment state
  | assignment :: rest ->
    let assignment, state = render_assignment ~aliases assignment state in
    let rest, state = render_assignments ~aliases rest state in
    concat [ assignment; text ","; break " "; rest ], state

and render_insert_row ~aliases ~columns assignments state =
  let values =
    List.map columns ~f:(fun column ->
      List.find_exn assignments ~f:(fun assignment ->
        Identifier.equal column assignment.Ast.column)
      |> fun assignment -> assignment.Ast.value)
  in
  let rec render_values values state =
    match values with
    | [] -> Template.Empty, state
    | [ value ] -> render_assignment_value ~aliases value state
    | value :: rest ->
      let value, state = render_assignment_value ~aliases value state in
      let rest, state = render_values rest state in
      concat [ value; text ", "; rest ], state
  in
  let values, state = render_values values state in
  concat [ text "("; values; text ")" ], state

and render_insert_rows ~aliases ~columns rows state =
  match rows with
  | [] -> Template.Empty, state
  | [ row ] -> render_insert_row ~aliases ~columns row state
  | row :: rest ->
    let row, state = render_insert_row ~aliases ~columns row state in
    let rest, state = render_insert_rows ~aliases ~columns rest state in
    concat [ row; text ","; break " "; rest ], state

and aliases_for_command (command : Ast.command) =
  match command.kind, command.from with
  | Ast.Insert, _ ->
    let target = command.source.source_id, "" in
    (match command.conflict with
     | Some (Ast.Do_update { excluded_source_id; _ }) ->
       [ command.source.source_id, "t0"; excluded_source_id, "excluded" ]
     | None | Some (Ast.Do_nothing _) -> [ target ])
  | Ast.Update, _ :: _ ->
    let sources = command.source :: command.from in
    List.mapi sources ~f:(fun index source ->
      source.Ast.source_id, Stdlib.Format.asprintf "t%d" index)
  | _ -> [ command.source.source_id, "" ]

and render_conflict_target target =
  List.map target ~f:(fun target -> quote_identifier target.Ast.target_column)
  |> separate ~by:(concat [ text ","; break " " ])

and where_clause ~aliases where_ parts state =
  match where_ with
  | None -> parts, state
  | Some condition ->
    let condition, state = render_condition ~aliases condition state in
    ( concat [ parts; break " "; text "WHERE"; nest (concat [ break " "; condition ]) ]
    , state )

and render_conflict ~aliases conflict parts state =
  match conflict with
  | Ast.Do_nothing None ->
    concat [ parts; break " "; text "ON CONFLICT DO NOTHING" ], state
  | Ast.Do_nothing (Some target) ->
    let target = render_conflict_target target in
    ( concat
        [ parts
        ; break " "
        ; text "ON CONFLICT ("
        ; nest (concat [ break ""; target ])
        ; break ""
        ; text ")"
        ; break " "
        ; text "DO NOTHING"
        ]
    , state )
  | Ast.Do_update { target; assignments; where_; _ } ->
    let target = render_conflict_target target in
    let assignments, state = render_assignments ~aliases assignments state in
    let parts =
      concat
        [ parts
        ; break " "
        ; text "ON CONFLICT ("
        ; nest (concat [ break ""; target ])
        ; break ""
        ; text ")"
        ; break " "
        ; text "DO UPDATE"
        ; break " "
        ; text "SET"
        ; nest (concat [ break " "; assignments ])
        ]
    in
    where_clause ~aliases where_ parts state

and render_target_source (source : Ast.source) =
  match source.Ast.kind with
  | Ast.Table table -> render_table_source table
  | Ast.Derived _ | Ast.Values _ | Ast.Cte _ -> assert false

and render_from_sources ~aliases (sources : Ast.source list) state =
  match sources with
  | [] -> Template.Empty, state
  | [ source ] ->
    let alias = alias_for aliases source.Ast.source_id in
    let source, state = render_source ~aliases source state in
    concat [ source; text " AS "; text alias ], state
  | source :: rest ->
    let alias = alias_for aliases source.Ast.source_id in
    let source, state = render_source ~aliases source state in
    let rest, state = render_from_sources ~aliases rest state in
    concat [ source; text " AS "; text alias; text ","; break " "; rest ], state

and render_command_ast (command : Ast.command) state =
  let render_body state =
    let aliases = aliases_for_command command in
    match command.kind with
    | Ast.Insert ->
      let columns, input, state =
        match command.insert_input with
        | Some (Ast.Rows rows) ->
          let first_row = List.hd_exn rows in
          let columns = List.map first_row ~f:(fun assignment -> assignment.Ast.column) in
          let rows, state = render_insert_rows ~aliases ~columns rows state in
          columns, concat [ text "VALUES"; nest (concat [ break " "; rows ]) ], state
        | Some (Ast.Select_rows selected) ->
          let columns =
            List.map selected.columns ~f:(fun column -> column.Ast.target_column)
          in
          let sqlite_insert_upsert =
            match state.dialect, command.conflict with
            | Dialect.Sqlite, Some _ -> true
            | Dialect.Postgresql, _ | Dialect.Sqlite, None -> false
          in
          let query, state =
            render_select_query
              ~parent_aliases:[]
              ~sqlite_insert_upsert
              selected.query
              state
          in
          columns, query, state
        | None | Some Ast.Mixed_sources -> assert false
      in
      let rendered_columns =
        List.map columns ~f:quote_identifier
        |> separate ~by:(concat [ text ","; break " " ])
      in
      let target_alias =
        let alias = alias_for aliases command.source.source_id in
        if String.is_empty alias then
          Template.Empty
        else
          concat [ text " AS "; text alias ]
      in
      let parts =
        concat
          [ text "INSERT INTO "
          ; render_target_source command.source
          ; target_alias
          ; text " ("
          ; nest (concat [ break ""; rendered_columns ])
          ; break ""
          ; text ")"
          ; break " "
          ; input
          ]
      in
      (match command.conflict with
       | None -> parts, state
       | Some conflict -> render_conflict ~aliases conflict parts state)
    | Ast.Update ->
      let assignments, state = render_assignments ~aliases command.assignments state in
      let target_alias = alias_for aliases command.source.source_id in
      let target_alias =
        if String.is_empty target_alias then
          Template.Empty
        else
          concat [ text " AS "; text target_alias ]
      in
      let parts =
        concat
          [ text "UPDATE "
          ; render_target_source command.source
          ; target_alias
          ; break " "
          ; text "SET"
          ; nest (concat [ break " "; assignments ])
          ]
      in
      let parts, state =
        match command.from with
        | [] -> parts, state
        | sources ->
          let sources, state = render_from_sources ~aliases sources state in
          concat [ parts; break " "; text "FROM "; nest sources ], state
      in
      where_clause ~aliases command.where_ parts state
    | Ast.Delete ->
      let parts = concat [ text "DELETE FROM "; render_target_source command.source ] in
      where_clause ~aliases command.where_ parts state
  in
  render_with command.ctes ~render_body state

and render_returning (returning : Ast.returning) state =
  let parts, state = render_command_ast returning.command state in
  let aliases =
    match state.dialect, returning.command.kind with
    | Dialect.Postgresql, Ast.Update -> aliases_for_command returning.command
    | Dialect.Postgresql, (Ast.Insert | Ast.Delete)
    | Dialect.Sqlite, (Ast.Insert | Ast.Update | Ast.Delete) ->
      [ returning.command.source.source_id, "" ]
  in
  let projection, state =
    render_expressions
      ~aliases
      ~separator:(concat [ text ","; break " " ])
      returning.projection
      state
  in
  ( concat [ parts; break " "; text "RETURNING"; nest (concat [ break " "; projection ]) ]
  , state )
;;

let finish (template, state) = template, List.rev state.parameters_rev

let result_query ~dialect query =
  let initial_state = initial_state_for dialect in
  match Lower.result_query_ast query with
  | Ast.Select query ->
    finish (render_select_query ~parent_aliases:[] query initial_state)
  | Ast.Returning returning -> finish (render_returning returning initial_state)
;;

let command ~dialect command =
  finish (render_command_ast (Lower.command_ast command) (initial_state_for dialect))
;;
