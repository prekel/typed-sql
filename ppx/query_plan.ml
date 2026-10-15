open! Base
module Q = Sql_query
module N = Native_type
module S = Typed_sql_schema.Schema_ir
module I = Typed_sql_schema.Identifier

type field =
  { name : string
  ; codec : Codec.t
  ; nullable : bool
  }

type parameter =
  { value : Q.parameter
  ; codec : Codec.t
  }

type t =
  { fields : field list
  ; parameters : parameter list
  }

type column =
  { name : string
  ; native : (N.t, Q.error) Result.t
  ; origin : S.column option
  ; modifier : int option
  ; identity : string
  }

type binding =
  { names : string list
  ; alias : bool
  ; columns : column list
  }

type scope =
  { bindings : binding list
  ; columns : column list
  ; outer : scope option
  ; grouped : string list option
  ; forbidden : string list
  }

type value =
  { native : N.t option
  ; origin : S.column option
  ; modifier : int option
  ; key : string
  ; aggregate : bool
  }

type result =
  { columns : column list
  ; command : bool
  }

type state =
  { schema : S.t
  ; mutable next : int
  ; mutable parameters : (Q.parameter * N.t) list
  }

type environment =
  { ctes : (string * column list option) list
  ; outer : scope option
  ; top : bool
  ; dml : bool
  ; lateral : scope option
  ; windows : (string * Q.window) list
  }

exception Invalid of Q.error

let reject offset message = Stdlib.raise (Invalid { Q.offset; message })

let get = function
  | Ok value -> value
  | Error error -> Stdlib.raise (Invalid error)
;;

let fresh state =
  let id = state.next in
  state.next <- id + 1;
  Int.to_string id
;;

let known offset (value : value) =
  match value.native with
  | Some native -> native
  | None -> reject offset "cannot infer parameter type without a SQL context"
;;

let value ?origin ?(modifier = Some (-1)) ?(aggregate = false) native key =
  { native; origin; modifier; key; aggregate }
;;

let empty_scope outer =
  { bindings = []; columns = []; outer; grouped = None; forbidden = [] }
;;

let native (column : column) = get column.native

let comparable offset typ =
  if not (N.comparable typ) then
    reject offset "PostgreSQL json has no equality or ordering operator; use jsonb"
;;

let key op values =
  op ^ "(" ^ String.concat ~sep:"," (List.map values ~f:(fun value -> value.key)) ^ ")"
;;

let scalar name = N.Scalar name

let is_aggregate = function
  | "count"
  | "sum"
  | "avg"
  | "min"
  | "max"
  | "bool_and"
  | "bool_or"
  | "string_agg"
  | "array_agg" -> true
  | _ -> false
;;

let name_of_call offset = function
  | [ name ] | [ "pg_catalog"; name ] -> name
  | _ -> reject offset "unsupported function namespace"
;;

let matches binding prefix =
  match prefix with
  | [] -> true
  | [ name ] ->
    Option.value_map (List.last binding.names) ~default:false ~f:(String.equal name)
  | _ -> (not binding.alias) && List.equal String.equal prefix binding.names
;;

let unique offset what = function
  | [ value ] -> value
  | [] -> reject offset ("unknown " ^ what)
  | _ -> reject offset ("ambiguous " ^ what)
;;

let rec resolve (scope : scope) offset names =
  match List.rev names with
  | [] -> reject offset "expected column name"
  | name :: qualifier ->
    let prefix = List.rev qualifier in
    let bindings =
      List.filter scope.bindings ~f:(fun binding -> matches binding prefix)
    in
    let columns =
      if List.is_empty prefix then
        scope.columns
      else (
        match
          bindings
        with
        | [] -> []
        | [ binding ] -> binding.columns
        | _ -> reject offset "ambiguous table qualifier")
    in
    let found = List.filter columns ~f:(fun column -> String.equal column.name name) in
    (match found, scope.outer with
     | [], Some outer when List.is_empty prefix || List.is_empty bindings ->
       resolve outer offset names
     | [], _ when (not (List.is_empty prefix)) && List.is_empty bindings ->
       reject offset "column qualifier does not name the statement source"
     | _ ->
       let column = unique offset ("column: " ^ name) found in
       if List.mem scope.forbidden column.identity ~equal:String.equal then
         reject offset "LATERAL reference requires an INNER or LEFT JOIN";
       Option.iter scope.grouped ~f:(fun allowed ->
         if not (List.mem allowed column.identity ~equal:String.equal) then
           reject offset "subquery uses an ungrouped outer column");
       column)
;;

let rename offset names columns =
  if Int.(List.length names > List.length columns) then
    reject offset "too many column aliases";
  List.mapi columns ~f:(fun i column ->
    match List.nth names i with
    | None -> column
    | Some name -> { column with name })
;;

let merge_bindings offset left right =
  List.iter right ~f:(fun binding ->
    List.iter left ~f:(fun previous ->
      if
        String.equal (List.last_exn binding.names) (List.last_exn previous.names)
        && (binding.alias
            || previous.alias
            || List.equal String.equal binding.names previous.names)
      then
        reject offset ("duplicate source name: " ^ List.last_exn binding.names)));
  left @ right
;;

let table state offset names =
  let schema, name =
    match names with
    | [ name ] -> "public", name
    | [ schema; name ] -> schema, name
    | _ -> reject offset "expected table or schema.table"
  in
  unique
    offset
    ("table: " ^ schema ^ "." ^ name)
    (List.filter (S.tables state.schema) ~f:(fun table ->
       String.equal name (I.to_string (S.table_name table))
       && Option.value_map (S.table_schema table) ~default:false ~f:(fun s ->
         String.equal schema (I.to_string s))))
;;

let table_columns state offset table =
  let id = fresh state in
  List.map (S.columns table) ~f:(fun column ->
    { name = I.to_string (S.column_name column)
    ; native = N.of_column_exact ~offset column
    ; origin = Some column
    ; modifier = S.column_postgresql_type_modifier column
    ; identity = id ^ "." ^ I.to_string (S.column_name column)
    })
;;

let bind state offset parameter typ =
  match
    List.find state.parameters ~f:(fun (previous, _) ->
      Int.equal previous.Q.start parameter.Q.start)
  with
  | Some (_, old) when not (N.equal old typ) ->
    reject offset "inconsistent parameter type contexts"
  | Some _ -> ()
  | None -> state.parameters <- (parameter, typ) :: state.parameters
;;

let common offset types =
  let types = List.filter types ~f:(fun typ -> not (N.equal typ N.Unknown)) in
  let types =
    match types with
    | [] -> []
    | first :: rest when List.for_all rest ~f:(N.equal first) -> types
    | _ -> List.map types ~f:N.base
  in
  match types with
  | [] -> scalar "text"
  | first :: rest ->
    let candidate =
      List.fold rest ~init:first ~f:(fun previous next ->
        if N.equal previous next then
          previous
        else if N.implicit previous next && not (N.implicit next previous) then
          next
        else
          previous)
    in
    if List.for_all types ~f:(fun actual -> N.implicit actual candidate) then
      candidate
    else
      reject offset "incompatible PostgreSQL result types"
;;

let type_name state offset (target : Q.type_name) =
  let names =
    match target.names with
    | [ "pg_catalog"; name ] -> [ name ]
    | names -> names
  in
  let builtin =
    match names with
    | [ name ] ->
      N.of_info
        ~offset
        { S.schema = I.of_string_exn "pg_catalog"
        ; name = I.of_string_exn name
        ; kind = Native_scalar
        }
    | _ -> Error { Q.offset; message = "not a built-in type" }
  in
  let typ =
    match builtin with
    | Ok typ -> typ
    | Error _ ->
      let wanted =
        match names with
        | [ name ] -> "public", name
        | [ schema; name ] -> schema, name
        | _ -> reject offset "invalid PostgreSQL type name"
      in
      let rec collect (info : S.postgresql_type_info) =
        let nested =
          match info.kind with
          | Native_domain base | Native_array base -> collect base
          | _ -> []
        in
        if
          String.equal (fst wanted) (I.to_string info.schema)
          && String.equal (snd wanted) (I.to_string info.name)
        then
          info :: nested
        else
          nested
      in
      let types =
        List.concat_map (S.tables state.schema) ~f:(fun table ->
          List.concat_map (S.columns table) ~f:(fun column ->
            Option.value_map (S.column_postgresql_type_info column) ~default:[] ~f:collect))
      in
      (match types with
       | [] -> reject offset "unknown or unsupported PostgreSQL cast type"
       | first :: _ -> get (N.of_info_exact ~offset first))
  in
  match target.dimensions with
  | 0 -> typ
  | 1 -> N.Array typ
  | _ -> reject offset "multidimensional arrays are unsupported"
;;

let origin_nullable (column : column) =
  match column.origin with
  | None -> true
  | Some origin ->
    (match
       S.column_postgresql_type_info origin, S.column_postgresql_attribute_not_null origin
     with
     | Some { kind = Native_domain _; _ }, None ->
       reject
         0
         "missing PostgreSQL attribute nullability for domain column; refresh the schema snapshot"
     | _ -> ());
    Option.value_map
      (S.column_postgresql_attribute_not_null origin)
      ~default:(S.column_nullable origin)
      ~f:not
;;

let rec expression_label (expr : Q.expression) =
  match expr.node with
  | Q.Column names -> List.last_exn names, 2
  | Call call -> List.last_exn call.name, 2
  | Cast (inner, target) ->
    let name, strength = expression_label inner in
    if Int.(strength = 2) then
      name, strength
    else
      List.last_exn target.names, 1
  | Case (_, _, otherwise) ->
    (match Option.map otherwise ~f:expression_label with
     | Some (name, 2) -> name, 2
     | _ -> "case", 1)
  | Exists _ -> "exists", 2
  | Scalar query -> query_label query, 2
  | _ -> "?column?", 0

and query_label (query : Q.statement) =
  match query.body with
  | Q.Select { projection = Q.Field (expr, name) :: _; _ } ->
    Option.value name ~default:(fst (expression_label expr))
  | Set (_, _, left, _) -> query_label left
  | Nested inner -> query_label inner
  | _ -> "?column?"
;;

let expr_name expr = fst (expression_label expr)

let resolve_window definitions (window : Q.window) =
  match window.parent with
  | None -> window
  | Some name ->
    let parent =
      match List.Assoc.find definitions name ~equal:String.equal with
      | Some parent -> parent
      | None -> reject window.offset ("unknown or forward window: " ^ name)
    in
    if window.direct then
      parent
    else (
      if Option.is_some parent.frame then
        reject window.offset "cannot copy a window with a frame clause";
      if not (List.is_empty window.partition) then
        reject window.offset "cannot override window PARTITION BY";
      if (not (List.is_empty parent.ordering)) && not (List.is_empty window.ordering) then
        reject window.offset "cannot override window ORDER BY";
      { window with
        parent = None
      ; partition = parent.partition
      ; ordering =
          (if List.is_empty window.ordering then
             parent.ordering
           else
             window.ordering)
      })
;;

let frame_expressions (window : Q.window) =
  Option.value_map window.frame ~default:[] ~f:(fun frame ->
    List.filter_map [ frame.first; frame.last ] ~f:(function
      | Q.Bounded (expr, _) -> Some expr
      | _ -> None))
;;

let window_expressions (window : Q.window) =
  window.partition
  @ List.map window.ordering ~f:(fun (expr, _, _) -> expr)
  @ frame_expressions window
;;

let rec dependencies (query : Q.statement) =
  let expr (value : Q.expression) = expression_dependencies value in
  let projection = function
    | Q.All _ -> []
    | Field (value, _) -> expr value
  in
  let body =
    match query.body with
    | Q.Select select ->
      Option.value_map select.from ~default:[] ~f:relation_dependencies
      @ List.concat_map select.projection ~f:projection
      @ List.concat_map select.windows ~f:(fun (_, window) ->
        List.concat_map (window_expressions window) ~f:expr)
      @ List.concat_map
          (Option.to_list select.conditions @ select.group @ Option.to_list select.having)
          ~f:expr
    | Set (_, _, left, right) -> dependencies left @ dependencies right
    | Nested inner -> dependencies inner
    | Insert (_, _, _, rows, input, conflict, returning) ->
      List.concat_map (Option.value rows ~default:[] |> List.concat) ~f:expr
      @ Option.value_map input ~default:[] ~f:dependencies
      @ (match conflict with
         | Some { action = Do_update (assignments, condition); _ } ->
           List.concat_map
             (List.map assignments ~f:snd @ Option.to_list condition)
             ~f:expr
         | _ -> [])
      @ List.concat_map returning ~f:projection
    | Update (_, _, assignments, sources, condition, returning) ->
      Option.value_map sources ~default:[] ~f:relation_dependencies
      @ List.concat_map (List.map assignments ~f:snd @ Option.to_list condition) ~f:expr
      @ List.concat_map returning ~f:projection
    | Delete (_, _, sources, condition, returning) ->
      Option.value_map sources ~default:[] ~f:relation_dependencies
      @ List.concat_map (Option.to_list condition) ~f:expr
      @ List.concat_map returning ~f:projection
  in
  let local = List.map query.ctes ~f:(fun cte -> cte.Q.name) in
  List.filter
    (body @ List.concat_map query.ctes ~f:(fun cte -> dependencies cte.query))
    ~f:(fun name -> not (List.mem local name ~equal:String.equal))

and relation_dependencies (relation : Q.relation) =
  match relation.relation with
  | Table { names = [ name ]; _ } -> [ name ]
  | Table _ -> []
  | Derived query | Lateral query -> dependencies query
  | Join (left, right, _, condition) ->
    relation_dependencies left
    @ relation_dependencies right
    @
      (match condition with
      | On expr -> expression_dependencies expr
      | _ -> [])

and expression_dependencies (expr : Q.expression) =
  match expr.node with
  | Scalar query | Exists query -> dependencies query
  | In_query (value, query, _) -> expression_dependencies value @ dependencies query
  | _ -> List.concat_map (children expr) ~f:expression_dependencies

and children (expr : Q.expression) =
  match expr.node with
  | Unary (_, value) | Cast (value, _) | Is_null (value, _) -> [ value ]
  | Binary (_, left, right) | Quantified (_, left, right, _) | Like_escape (left, right)
    -> [ left; right ]
  | Between (value, low, high, _) -> [ value; low; high ]
  | In_list (value, values, _) -> value :: values
  | Case (value, branches, otherwise) ->
    Option.to_list value
    @ List.concat_map branches ~f:(fun (a, b) -> [ a; b ])
    @ Option.to_list otherwise
  | Call call ->
    call.args
    @ List.map call.order ~f:(fun (expr, _, _) -> expr)
    @ Option.to_list call.filter
    @ Option.value_map call.over ~default:[] ~f:window_expressions
  | In_query (value, _, _) -> [ value ]
  | Column _
  | Parameter_value _
  | String_literal _
  | Number_literal _
  | Bool_literal _
  | Null_literal
  | Default
  | Scalar _
  | Exists _ -> []
;;

let rec has_window (expr : Q.expression) =
  match expr.node with
  | Call { over = Some _; _ } -> true
  | _ -> List.exists (children expr) ~f:has_window
;;

let rec infer
          state
          environment
          (scope : scope)
          ?expected
          ?(inside_aggregate = false)
          ?(inside_window = false)
          ?(allow_window = false)
          (expr : Q.expression)
  =
  let offset = expr.offset in
  let infer_full = infer in
  let infer ?expected expr =
    infer
      state
      environment
      scope
      ?expected
      ~inside_aggregate
      ~inside_window
      ~allow_window
      expr
  in
  let boolean expr =
    let result = infer ~expected:(scalar "bool") expr in
    if not (N.equal (known expr.Q.offset result) (scalar "bool")) then
      reject expr.offset "boolean predicate requires bool";
    result
  in
  let context values =
    let found = List.filter_map values ~f:(fun value -> value.native) in
    match found with
    | [] -> Option.value expected ~default:(scalar "text")
    | first :: _ -> first
  in
  let finish typ ?origin ?(aggregate = false) values =
    value ?origin ~aggregate (Some typ) (key (expr_name expr) values)
  in
  match expr.node with
  | Column names ->
    let column = resolve scope offset names in
    value
      ?origin:column.origin
      ~modifier:column.modifier
      (Some (native column))
      column.identity
  | Parameter_value parameter ->
    Option.iter expected ~f:(bind state offset parameter);
    value expected ("$" ^ Int.to_string parameter.start)
  | String_literal text -> value expected ("str:" ^ text)
  | Null_literal -> value expected "null"
  | Number_literal text ->
    let typ =
      match Int64.of_string_opt text with
      | Some n when Int64.(n >= -2147483648L && n <= 2147483647L) -> scalar "int4"
      | Some _ -> scalar "int8"
      | None -> scalar "numeric"
    in
    value (Some typ) ("num:" ^ text)
  | Bool_literal b -> value (Some (scalar "bool")) (Bool.to_string b)
  | Default -> reject offset "DEFAULT is only supported in assigned values"
  | Unary ("not", expr) ->
    let inner = boolean expr in
    finish (scalar "bool") ~aggregate:inner.aggregate [ inner ]
  | Unary (_, expr) ->
    let inner = infer ?expected expr in
    let typ = known offset inner in
    if not (N.numeric typ) then
      reject offset "numeric unary operator requires a numeric operand";
    finish typ ~aggregate:inner.aggregate [ inner ]
  | Binary (("and" | "or"), left, right) ->
    let left = boolean left
    and right = boolean right in
    finish (scalar "bool") ~aggregate:(left.aggregate || right.aggregate) [ left; right ]
  | Binary ((("->" | "->>" | "#>" | "#>>") as op), left, right) ->
    let a = infer left in
    let typ = N.base (known left.offset a) in
    if not (List.exists [ scalar "json"; scalar "jsonb" ] ~f:(N.equal typ)) then
      reject offset "JSON extraction requires json or jsonb";
    let initial = infer right in
    let expected =
      if String.is_prefix op ~prefix:"#" then
        N.Array (scalar "text")
      else (
        match
          Option.map initial.native ~f:N.base
        with
        | Some (N.Scalar ("int2" | "int4")) -> scalar "int4"
        | _ -> scalar "text")
    in
    let b = infer ~expected right in
    if not (N.implicit (known right.offset b) expected) then
      reject right.offset "invalid JSON extraction key or path type";
    let result =
      if String.is_suffix op ~suffix:">>" then
        scalar "text"
      else
        typ
    in
    finish result ~aggregate:(a.aggregate || b.aggregate) [ a; b ]
  | Binary (op, left, right) ->
    let a = infer left
    and b = infer right in
    let typ =
      if String.equal op "||" || String.equal op "like" || String.equal op "ilike" then
        scalar "text"
      else if List.mem [ "+"; "-"; "*"; "/"; "%" ] op ~equal:String.equal then (
        let known = List.filter_map [ a; b ] ~f:(fun value -> value.native) in
        if List.is_empty known then
          reject offset "cannot infer numeric operator types"
        else
          common offset known)
      else
        context [ a; b ]
    in
    let a =
      if Option.is_none a.native then
        infer ~expected:typ left
      else
        a
    in
    let b =
      if Option.is_none b.native then
        infer ~expected:typ right
      else
        b
    in
    let comparison =
      List.mem
        [ "="
        ; "<>"
        ; "!="
        ; "<"
        ; ">"
        ; "<="
        ; ">="
        ; "is distinct from"
        ; "is not distinct from"
        ]
        op
        ~equal:String.equal
    in
    if comparison then (
      comparable offset typ;
      if not (N.compatible (known offset a) (known offset b)) then
        reject offset "incompatible PostgreSQL operand types")
    else if String.equal op "||" || String.equal op "like" || String.equal op "ilike" then (
      if not (N.text (known offset a) && N.text (known offset b)) then
        reject offset "text operator requires text operands")
    else if not (N.numeric (known offset a) && N.numeric (known offset b)) then
      reject offset "arithmetic requires numeric operands";
    if
      String.equal op "%"
      && List.exists
           [ known offset a; known offset b ]
           ~f:(fun typ ->
             match N.base typ with
             | N.Scalar ("float4" | "float8") -> true
             | _ -> false)
    then
      reject offset "PostgreSQL floating-point remainder is unsupported";
    let result =
      if comparison || String.equal op "like" || String.equal op "ilike" then
        scalar "bool"
      else if
        List.mem [ "+"; "-"; "*"; "/" ] op ~equal:String.equal
        && N.numeric (known offset a)
        && N.numeric (known offset b)
        && (N.equal (N.base (known offset a)) (scalar "float4")
            || N.equal (N.base (known offset b)) (scalar "float4"))
        && not (N.equal (N.base (known offset a)) (N.base (known offset b)))
      then
        scalar "float8"
      else
        N.base typ
    in
    value (Some result) (key op [ a; b ]) ~aggregate:(a.aggregate || b.aggregate)
  | Cast (inner, target) ->
    let modifier =
      get
        (Type_modifier.of_type_name target
         |> Result.map_error ~f:(fun (error : Q.error) -> { error with Q.offset }))
    in
    let cast_key =
      String.concat ~sep:"." target.names
      ^ String.concat (List.init target.dimensions ~f:(fun _ -> "[]"))
      ^ ":"
      ^ Int.to_string modifier
    in
    let target = type_name state offset target in
    let source = infer ~expected:target inner in
    let sensitive =
      match target with
      | N.Scalar
          ( "varchar"
          | "bpchar"
          | "numeric"
          | "time"
          | "timestamp"
          | "timestamptz"
          | "interval" )
      | N.Array
          (N.Scalar
             ( "varchar"
             | "bpchar"
             | "numeric"
             | "time"
             | "timestamp"
             | "timestamptz"
             | "interval" )) -> true
      | _ -> false
    in
    let origin =
      if not (N.equal (known offset source) target) then
        None
      else (
        match
          source.origin
        with
        | None -> None
        | Some column ->
          if not sensitive then
            source.origin
          else (
            match
              S.column_postgresql_type_modifier column
            with
            | None ->
              reject
                offset
                "same-type cast column origin requires type modifier metadata; refresh the schema snapshot"
            | Some original ->
              if Int.equal original modifier then
                source.origin
              else
                None))
    in
    if not (N.explicit (known offset source) target) then
      reject offset "unsupported PostgreSQL cast";
    if
      N.equal (known offset source) target
      && ((not sensitive) || Option.equal Int.equal source.modifier (Some modifier))
    then
      { source with native = Some target; origin; modifier = Some modifier }
    else
      value
        ?origin
        ~modifier:(Some modifier)
        ~aggregate:source.aggregate
        (Some target)
        (key ("cast:" ^ cast_key) [ source ])
  | Like_escape (inner, escape) ->
    let result = boolean inner in
    let escaped = infer ~expected:(scalar "text") escape in
    if not (N.text (known escape.Q.offset escaped)) then
      reject escape.offset "ESCAPE requires text";
    finish
      (scalar "bool")
      ~aggregate:(result.aggregate || escaped.aggregate)
      [ result; escaped ]
  | Is_null (inner, _) ->
    let source = infer inner in
    if
      Option.is_none source.native
      &&
      match inner.node with
      | Parameter_value _ -> true
      | _ -> false
    then
      reject offset "cannot infer parameter type in IS NULL";
    finish (scalar "bool") ~aggregate:source.aggregate [ source ]
  | Between (inner, low, high, _) ->
    let values = [ inner; low; high ] in
    let inferred = List.map values ~f:infer in
    let typ = context inferred in
    let checked =
      List.map values ~f:(fun expr ->
        let result = infer ~expected:typ expr in
        if not (N.compatible typ (known expr.offset result)) then
          reject expr.offset "incompatible PostgreSQL operand types";
        result)
    in
    comparable offset typ;
    finish
      (scalar "bool")
      ~aggregate:(List.exists checked ~f:(fun x -> x.aggregate))
      checked
  | In_list (inner, items, _) ->
    let values = inner :: items in
    let first = List.map values ~f:infer in
    let typ = common offset (List.filter_map first ~f:(fun value -> value.native)) in
    let checked =
      List.map values ~f:(fun expr ->
        let result = infer ~expected:typ expr in
        if not (N.implicit (known expr.offset result) typ) then
          reject expr.offset "incompatible PostgreSQL IN operand types";
        result)
    in
    comparable offset typ;
    finish
      (scalar "bool")
      ~aggregate:(List.exists checked ~f:(fun x -> x.aggregate))
      checked
  | Case (operand, branches, otherwise) ->
    let input =
      Option.map operand ~f:(fun expr ->
        let first = infer expr in
        match first.native with
        | Some _ -> first
        | None -> infer ~expected:(scalar "text") expr)
    in
    List.iter branches ~f:(fun (condition, _) ->
      match input with
      | None -> ignore (boolean condition : value)
      | Some input ->
        let result = infer ~expected:(known offset input) condition in
        if not (N.compatible (known offset input) (known offset result)) then
          reject condition.offset "incompatible CASE comparison types");
    let outputs = Option.to_list otherwise @ List.map branches ~f:snd in
    let first = List.map outputs ~f:infer in
    let typ = common offset (List.filter_map first ~f:(fun x -> x.native)) in
    let results =
      List.map outputs ~f:(fun expr ->
        let result = infer ~expected:typ expr in
        if not (N.implicit (known expr.offset result) typ) then
          reject expr.offset "incompatible CASE result types";
        result)
    in
    finish
      typ
      ~aggregate:
        (List.exists (List.map (children expr) ~f:infer) ~f:(fun x -> x.aggregate))
      results
  | Call call when Option.is_some call.over ->
    if not allow_window then
      reject offset "window functions are not allowed in this clause";
    if inside_window || inside_aggregate then
      reject offset "window functions cannot be nested or used inside aggregates";
    let window = resolve_window environment.windows (Option.value_exn call.over) in
    let window_values = infer_window state environment scope window in
    let name = name_of_call offset call.name in
    let infer_arg ?expected arg =
      infer_full state environment scope ?expected ~inside_window:true arg
    in
    let arity choices =
      if not (List.mem choices (List.length call.args) ~equal:Int.equal) then
        reject offset "incorrect window function argument count"
    in
    let integer arg =
      let result = infer_arg ~expected:(scalar "int4") arg in
      if not (N.implicit (known arg.Q.offset result) (scalar "int4")) then
        reject arg.offset "window function argument requires integer";
      result
    in
    let typ, arguments =
      if is_aggregate name then (
        if call.distinct || not (List.is_empty call.order) then
          reject offset "DISTINCT and aggregate ORDER BY are not supported with OVER";
        let result =
          infer_call
            state
            environment
            scope
            ?expected
            ~inside_aggregate:false
            ~inside_window:true
            ~allow_window:false
            ~windowed:true
            expr
            { call with over = None }
        in
        known offset result, [ result ])
      else (
        if
          call.star
          || call.distinct
          || (not (List.is_empty call.order))
          || Option.is_some call.filter
        then
          reject offset "aggregate modifiers require a window aggregate";
        match name with
        | "row_number" | "rank" | "dense_rank" ->
          arity [ 0 ];
          scalar "int8", []
        | "percent_rank" | "cume_dist" ->
          arity [ 0 ];
          scalar "float8", []
        | "ntile" ->
          arity [ 1 ];
          scalar "int4", [ integer (List.hd_exn call.args) ]
        | "first_value" | "last_value" | "nth_value" | "lag" | "lead" ->
          arity
            (if String.equal name "nth_value" then
               [ 2 ]
             else if String.equal name "lag" || String.equal name "lead" then
               [ 1; 2; 3 ]
             else
               [ 1 ]);
          let first = List.hd_exn call.args in
          let initial = infer_arg first in
          let default = Option.map (List.nth call.args 2) ~f:infer_arg in
          let known_types =
            List.filter_map (initial :: Option.to_list default) ~f:(fun value ->
              value.native)
          in
          if List.is_empty known_types then
            reject offset "cannot infer polymorphic window argument type; add a cast";
          let typ = common offset known_types in
          let value = infer_arg ~expected:typ first in
          if not (N.implicit (known offset value) typ) then
            reject offset "incompatible window value type";
          let remaining =
            List.filter_mapi call.args ~f:(fun index arg ->
              if Int.(index = 0) then
                None
              else if Int.(index = 1) then
                Some (integer arg)
              else (
                let value = infer_arg ~expected:typ arg in
                if not (N.implicit (known offset value) typ) then
                  reject arg.offset "incompatible window default type";
                Some value))
          in
          typ, value :: remaining
        | _ -> reject offset "OVER requires a supported window or aggregate function")
    in
    value
      (Some typ)
      (key name (arguments @ window_values))
      ~aggregate:
        (List.exists (arguments @ window_values) ~f:(fun value -> value.aggregate))
  | Call call ->
    infer_call
      state
      environment
      scope
      ?expected
      ~inside_aggregate
      ~inside_window
      ~allow_window
      ~windowed:false
      expr
      call
  | Scalar query ->
    let result =
      analyze
        state
        { environment with outer = Some scope; top = false; dml = false }
        query
    in
    let column = unique offset "scalar subquery column" result.columns in
    value (Some (native column)) ("subquery:" ^ Int.to_string offset)
  | Exists query ->
    ignore
      (analyze
         state
         { environment with outer = Some scope; top = false; dml = false }
         query
       : result);
    value (Some (scalar "bool")) ("exists:" ^ Int.to_string offset)
  | In_query (inner, query, _) ->
    let result =
      analyze
        state
        { environment with outer = Some scope; top = false; dml = false }
        query
    in
    let column = unique offset "IN subquery column" result.columns in
    let typ = native column in
    let input = infer ~expected:typ inner in
    if not (N.compatible typ (known offset input)) then
      reject offset "incompatible IN subquery types";
    comparable offset typ;
    finish (scalar "bool") ~aggregate:input.aggregate [ input ]
  | Quantified (_, inner, right, _) ->
    let typ =
      match right.node with
      | Scalar query ->
        let result =
          analyze
            state
            { environment with outer = Some scope; top = false; dml = false }
            query
        in
        native (unique offset "ANY/ALL subquery column" result.columns)
      | _ ->
        let input = infer inner in
        let array =
          infer ?expected:(Option.map input.native ~f:(fun typ -> N.Array typ)) right
        in
        (match known offset array with
         | N.Array element -> element
         | _ -> reject right.offset "ANY/ALL requires an array operand")
    in
    let input = infer ~expected:typ inner in
    if not (N.compatible typ (known offset input)) then
      reject offset "incompatible ANY/ALL operands";
    comparable offset typ;
    finish (scalar "bool") ~aggregate:input.aggregate [ input ]

and infer_call
      state
      environment
      (scope : scope)
      ?expected
      ~inside_aggregate
      ~inside_window
      ~allow_window
      ~windowed
      (expr : Q.expression)
      (call : Q.call)
  =
  let offset = expr.offset in
  ignore (expected : N.t option);
  let name = name_of_call offset call.name in
  let aggregate_name = is_aggregate name in
  let aggregate = aggregate_name && not windowed in
  if aggregate && inside_aggregate then
    reject offset "aggregate calls cannot be nested";
  if
    (not aggregate_name)
    && (call.star
        || call.distinct
        || (not (List.is_empty call.order))
        || Option.is_some call.filter)
  then
    reject offset "aggregate modifiers require an aggregate function";
  let infer ?expected value =
    infer
      state
      environment
      scope
      ?expected
      ~inside_aggregate:(inside_aggregate || aggregate)
      ~inside_window
      ~allow_window
      value
  in
  let expect_count n =
    if not (Int.equal (List.length call.args) n) then
      reject offset "incorrect function argument count"
  in
  if String.equal name "coalesce" then (
    if List.is_empty call.args then
      reject offset "COALESCE requires arguments";
    let initial = List.map call.args ~f:infer in
    let typ = common offset (List.filter_map initial ~f:(fun value -> value.native)) in
    let args =
      List.map call.args ~f:(fun expr ->
        let result = infer ~expected:typ expr in
        if not (N.implicit (known expr.Q.offset result) typ) then
          reject expr.offset "incompatible COALESCE result types";
        result)
    in
    value
      (Some typ)
      (key name args)
      ~aggregate:(List.exists args ~f:(fun arg -> arg.aggregate)))
  else if String.equal name "nullif" then (
    expect_count 2;
    let args = List.map call.args ~f:infer in
    let typ = common offset (List.filter_map args ~f:(fun value -> value.native)) in
    let args = List.map call.args ~f:(infer ~expected:typ) in
    comparable offset typ;
    let first = known offset (List.hd_exn args) in
    let integer = function
      | N.Scalar ("int2" | "int4" | "int8") -> true
      | _ -> false
    in
    let typ =
      if N.text first then
        scalar "text"
      else if
        integer (N.base first)
        && List.for_all args ~f:(fun arg -> integer (N.base (known offset arg)))
      then
        N.base first
      else
        typ
    in
    value
      (Some typ)
      (key name args)
      ~aggregate:(List.exists args ~f:(fun arg -> arg.aggregate)))
  else if not aggregate_name then (
    let text = scalar "text"
    and integer = scalar "int4" in
    let count = List.length call.args in
    let arity sizes =
      if not (List.mem sizes count ~equal:Int.equal) then
        reject offset "incorrect function argument count"
    in
    let typed types =
      List.map2_exn call.args types ~f:(fun expr expected ->
        let result = infer ~expected expr in
        if not (N.implicit (known expr.Q.offset result) expected) then
          reject expr.offset "unsupported PostgreSQL function overload";
        result)
    in
    let result, args =
      match name with
      | "lower" | "upper" ->
        arity [ 1 ];
        text, typed [ text ]
      | "length" | "char_length" | "character_length" | "octet_length" ->
        arity [ 1 ];
        let initial = infer (List.hd_exn call.args) in
        let typ =
          match initial.native with
          | Some (N.Scalar "bytea")
            when String.equal name "length" || String.equal name "octet_length" ->
            scalar "bytea"
          | Some (N.Scalar "bpchar") -> scalar "bpchar"
          | _ -> text
        in
        integer, typed [ typ ]
      | "btrim" | "ltrim" | "rtrim" ->
        arity [ 1; 2 ];
        text, typed (List.init count ~f:(fun _ -> text))
      | "substring" | "substr" ->
        arity [ 2; 3 ];
        if
          not
            (List.exists (List.tl_exn call.args) ~f:(fun arg ->
               Option.value_map (infer arg).native ~default:false ~f:(fun typ ->
                 N.implicit typ integer)))
        then
          reject
            offset
            "positional substring requires an integer type context; regex overloads are unsupported";
        text, typed (text :: List.init (count - 1) ~f:(fun _ -> integer))
      | "replace" ->
        arity [ 3 ];
        text, typed [ text; text; text ]
      | "concat" ->
        if Int.(count = 0) then
          reject offset "CONCAT requires arguments";
        ( text
        , List.map call.args ~f:(fun expr ->
            let result = infer expr in
            ignore (known expr.Q.offset result : N.t);
            result) )
      | "abs" ->
        arity [ 1 ];
        let initial = infer (List.hd_exn call.args) in
        let typ = Option.value_map initial.native ~default:(scalar "float8") ~f:N.base in
        let result = infer ~expected:typ (List.hd_exn call.args) in
        if not (N.numeric typ) then
          reject offset "ABS requires numeric input";
        typ, [ result ]
      | "round" ->
        arity [ 1; 2 ];
        let initial = infer (List.hd_exn call.args) in
        let typ =
          if Int.(count = 2) then
            scalar "numeric"
          else (
            match
              Option.map initial.native ~f:N.base
            with
            | Some (N.Scalar "numeric") -> scalar "numeric"
            | _ -> scalar "float8")
        in
        ( typ
        , typed
            (if Int.(count = 1) then
               [ typ ]
             else
               [ typ; integer ]) )
      | _ -> reject offset ("unsupported PostgreSQL function: " ^ name)
    in
    value
      (Some result)
      (key name args)
      ~aggregate:(List.exists args ~f:(fun arg -> arg.aggregate)))
  else (
    let rec references (expr : Q.expression) =
      match expr.node with
      | Q.Column names -> [ resolve scope expr.offset names ]
      | Scalar _ | Exists _ -> []
      | _ -> List.concat_map (children expr) ~f:references
    in
    let references =
      List.concat_map (call.args @ Option.to_list call.filter) ~f:references
    in
    if
      (not (List.is_empty references))
      && List.for_all references ~f:(fun column ->
        not
          (List.exists scope.columns ~f:(fun local ->
             String.equal local.identity column.identity)))
    then
      reject offset "aggregates belonging to an outer query level are unsupported";
    if
      call.star
      && ((not (String.equal name "count"))
          || call.distinct
          || not (List.is_empty call.args))
    then
      reject offset "only COUNT(*) accepts star";
    if not call.star then
      expect_count
        (if String.equal name "string_agg" then
           2
         else
           1);
    let string_context =
      if String.equal name "string_agg" then (
        let known_args =
          List.map call.args ~f:infer |> List.filter_map ~f:(fun value -> value.native)
        in
        if List.exists known_args ~f:(fun typ -> N.equal (N.base typ) (scalar "bytea"))
        then
          scalar "bytea"
        else
          scalar "text")
      else
        scalar "text"
    in
    let args =
      List.map call.args ~f:(fun expr ->
        let expected =
          if String.equal name "bool_and" || String.equal name "bool_or" then
            Some (scalar "bool")
          else if String.equal name "string_agg" then
            Some string_context
          else
            None
        in
        infer ?expected expr)
    in
    let first =
      if call.star then
        scalar "int8"
      else
        known offset (List.hd_exn args)
    in
    let result =
      match name, N.base first with
      | "count", _ -> scalar "int8"
      | "sum", N.Scalar ("int2" | "int4") -> scalar "int8"
      | "sum", N.Scalar "int8" -> scalar "numeric"
      | "sum", N.Scalar ("numeric" | "float4" | "float8" | "interval") -> N.base first
      | "avg", N.Scalar ("int2" | "int4" | "int8" | "numeric") -> scalar "numeric"
      | "avg", N.Scalar ("float4" | "float8") -> scalar "float8"
      | "avg", N.Scalar "interval" -> N.base first
      | ("min" | "max"), N.Scalar "varchar" -> scalar "text"
      | ( ("min" | "max")
        , ( N.Scalar
              ( "int2"
              | "int4"
              | "int8"
              | "float4"
              | "float8"
              | "numeric"
              | "text"
              | "bpchar"
              | "date"
              | "time"
              | "timestamp"
              | "timestamptz"
              | "interval" )
          | N.Enum _ | N.Array _ ) ) -> N.base first
      | ("bool_and" | "bool_or"), N.Scalar "bool" -> scalar "bool"
      | "array_agg", N.Array _ ->
        reject offset "multidimensional array_agg is unsupported"
      | "array_agg", _ -> N.Array first
      | "string_agg", N.Scalar ("text" | "varchar" | "bpchar" | "bytea") ->
        List.iter args ~f:(fun value ->
          if not (N.compatible first (known offset value)) then
            reject offset "incompatible string_agg arguments");
        if N.text first then
          scalar "text"
        else
          first
      | _ -> reject offset "unsupported PostgreSQL aggregate overload"
    in
    if call.distinct then
      List.iter args ~f:(fun value -> comparable offset (known offset value));
    List.iter call.order ~f:(fun (order, _, _) ->
      let ordered = infer order in
      comparable order.Q.offset (known order.offset ordered);
      if
        call.distinct
        && not (List.exists args ~f:(fun value -> String.equal value.key ordered.key))
      then
        reject order.offset "aggregate DISTINCT ORDER BY must occur in arguments");
    Option.iter call.filter ~f:(fun filter ->
      let result = infer ~expected:(scalar "bool") filter in
      if not (N.equal (known filter.Q.offset result) (scalar "bool")) then
        reject filter.offset "FILTER requires bool");
    value
      (Some result)
      (key name args)
      ~aggregate:(aggregate || List.exists args ~f:(fun value -> value.aggregate)))

and infer_window state environment scope (window : Q.window) =
  let infer_full = infer in
  let infer expr =
    let first = infer state environment scope ~inside_window:true expr in
    if Option.is_none first.native then
      infer state environment scope ~inside_window:true ~expected:(scalar "text") expr
    else
      first
  in
  let partition =
    List.map window.partition ~f:(fun expr ->
      let value = infer expr in
      comparable expr.Q.offset (known expr.offset value);
      value)
  in
  let ordered =
    List.map window.ordering ~f:(fun (expr, _, _) ->
      let value = infer expr in
      comparable expr.Q.offset (known expr.offset value);
      value)
  in
  let offsets =
    Option.value_map window.frame ~default:[] ~f:(fun frame ->
      let rank = function
        | Q.Unbounded true -> 0
        | Bounded (_, true) -> 1
        | Current_row -> 2
        | Bounded (_, false) -> 3
        | Unbounded false -> 4
      in
      if
        Int.(
          rank frame.first = 4
          || rank frame.last = 0
          || rank frame.first > rank frame.last)
      then
        reject window.offset "invalid window frame boundaries";
      if String.equal frame.mode "groups" && List.is_empty ordered then
        reject window.offset "GROUPS requires window ORDER BY";
      let expected =
        if not (String.equal frame.mode "range") then
          scalar "int8"
        else if List.is_empty (frame_expressions window) then
          scalar "int8"
        else (
          let ordered = unique window.offset "RANGE ORDER BY expression" ordered in
          match N.base (known window.offset ordered) with
          | N.Scalar ("date" | "time" | "timestamp" | "timestamptz" | "interval") ->
            scalar "interval"
          | N.Scalar "float4" -> scalar "float8"
          | typ when N.numeric typ -> typ
          | _ -> reject window.offset "unsupported RANGE offset type")
      in
      List.map (frame_expressions window) ~f:(fun expr ->
        let value = infer_full state environment (empty_scope None) ~expected expr in
        if value.aggregate || not (N.implicit (known expr.Q.offset value) expected) then
          reject expr.offset "invalid window frame offset type";
        value))
  in
  partition @ ordered @ offsets

and relation state environment (source : Q.relation) : scope =
  let bindings, columns =
    match source.relation with
    | Q.Table reference ->
      let cte =
        match reference.names with
        | [ name ] -> List.Assoc.find environment.ctes name ~equal:String.equal
        | _ -> None
      in
      let columns, names =
        match cte with
        | Some (Some columns) ->
          let identity = fresh state in
          ( List.map columns ~f:(fun column ->
              { column with identity = identity ^ "." ^ column.name })
          , reference.names )
        | Some None ->
          reject reference.offset "CTE without RETURNING cannot be used as a relation"
        | None ->
          let table = table state reference.offset reference.names in
          ( table_columns state reference.offset table
          , [ Option.value_map (S.table_schema table) ~default:"public" ~f:I.to_string
            ; I.to_string (S.table_name table)
            ] )
      in
      [ { names; alias = false; columns } ], columns
    | (Derived query | Lateral query) as kind ->
      let outer =
        match kind with
        | Q.Lateral _ -> Option.first_some environment.lateral environment.outer
        | _ -> environment.outer
      in
      let result =
        analyze state { environment with outer; top = false; dml = false } query
      in
      if result.command then
        reject source.offset "derived table requires returned columns";
      let identity = fresh state in
      ( []
      , List.map result.columns ~f:(fun column ->
          { column with identity = identity ^ "." ^ column.name }) )
    | Join (left, right, kind, condition) ->
      let left = relation state environment left in
      let forbidden =
        match kind with
        | Q.Right | Full -> List.map left.columns ~f:(fun column -> column.identity)
        | _ -> []
      in
      let preceding =
        match environment.lateral with
        | None -> { left with forbidden }
        | Some previous ->
          { left with
            bindings = merge_bindings source.offset previous.bindings left.bindings
          ; columns = previous.columns @ left.columns
          ; forbidden = previous.forbidden @ forbidden
          }
      in
      let right = relation state { environment with lateral = Some preceding } right in
      let bindings = merge_bindings source.offset left.bindings right.bindings in
      let scope =
        { bindings
        ; columns = left.columns @ right.columns
        ; outer = environment.outer
        ; grouped = None
        ; forbidden = []
        }
      in
      let using =
        match condition with
        | Q.On condition ->
          ignore (predicate state environment scope condition : value);
          []
        | No_condition -> []
        | Using columns ->
          List.map columns ~f:(fun column ->
            match column.Q.names with
            | [ name ] -> name
            | _ -> reject column.offset "USING requires unqualified column names")
        | Natural ->
          List.filter_map left.columns ~f:(fun column ->
            if
              List.exists right.columns ~f:(fun other ->
                String.equal other.name column.name)
            then
              Some column.name
            else
              None)
      in
      let merged =
        List.fold using ~init:[] ~f:(fun acc name ->
          if List.exists acc ~f:(fun column -> String.equal column.name name) then
            reject source.offset "duplicate USING column";
          let a =
            unique
              source.offset
              ("USING column: " ^ name)
              (List.filter left.columns ~f:(fun column -> String.equal column.name name))
          in
          let b =
            unique
              source.offset
              ("USING column: " ^ name)
              (List.filter right.columns ~f:(fun column -> String.equal column.name name))
          in
          let typ = common source.offset [ native a; native b ] in
          comparable source.offset typ;
          let selected =
            match kind with
            | Q.Full -> None
            | Right when N.equal (native b) typ -> Some b
            | (Inner | Left) when N.equal (native a) typ -> Some a
            | Inner when N.equal (native b) typ -> Some b
            | _ -> None
          in
          let origin = Option.bind selected ~f:(fun column -> column.origin) in
          let identity =
            Option.value_map selected ~default:(fresh state) ~f:(fun column ->
              column.identity)
          in
          acc
          @ [ { name
              ; native = Ok typ
              ; origin
              ; modifier = Option.bind selected ~f:(fun column -> column.modifier)
              ; identity
              }
            ])
      in
      let remaining columns =
        List.filter columns ~f:(fun column ->
          not (List.mem using column.name ~equal:String.equal))
      in
      bindings, merged @ remaining left.columns @ remaining right.columns
  in
  let columns = rename source.offset source.columns columns in
  let bindings =
    match source.alias with
    | Some name -> [ { names = [ name ]; alias = true; columns } ]
    | None -> bindings
  in
  { bindings; columns; outer = environment.outer; grouped = None; forbidden = [] }

and predicate state environment (scope : scope) (expr : Q.expression) =
  let result = infer state environment scope ~expected:(scalar "bool") expr in
  if not (N.equal (known expr.offset result) (scalar "bool")) then
    reject expr.offset "boolean predicate requires bool";
  if result.aggregate then
    reject expr.offset "aggregate is not allowed in this clause";
  result

and output_label state environment scope (expr : Q.expression) =
  match expr.node with
  | Scalar query ->
    let result =
      analyze
        state
        { environment with outer = Some scope; top = false; dml = false }
        query
    in
    (unique expr.offset "scalar subquery column" result.columns).name, 2
  | Cast (inner, target) ->
    let name, strength = output_label state environment scope inner in
    if Int.equal strength 2 then
      name, strength
    else
      List.last_exn target.names, 1
  | Case (_, _, Some otherwise) ->
    let name, strength = output_label state environment scope otherwise in
    if Int.equal strength 2 then
      name, strength
    else
      "case", 1
  | _ -> expression_label expr

and project
      state
      environment
      (scope : scope)
      ?expected
      ?(defer = false)
      ?(allow_window = false)
      projection
  =
  List.concat_mapi projection ~f:(fun index -> function
    | Q.All reference ->
      if List.is_empty reference.names then
        scope.columns
      else
        (unique
           reference.offset
           "table qualifier"
           (List.filter scope.bindings ~f:(fun binding -> matches binding reference.names)))
          .columns
    | Field (expr, name) ->
      let expectation = Option.bind expected ~f:(fun types -> List.nth types index) in
      let first =
        infer state environment scope ?expected:expectation ~allow_window expr
      in
      let result =
        if Option.is_none first.native && not defer then
          infer
            state
            environment
            scope
            ~expected:(Option.value expectation ~default:(scalar "text"))
            ~allow_window
            expr
        else
          first
      in
      [ { name =
            Option.value name ~default:(fst (output_label state environment scope expr))
        ; native = Ok (Option.value result.native ~default:N.Unknown)
        ; origin = result.origin
        ; modifier = result.modifier
        ; identity = result.key
        }
      ])

and check_group state environment (scope : scope) allowed (expr : Q.expression) =
  let result = infer state environment scope ~allow_window:true expr in
  if List.mem allowed result.key ~equal:String.equal then
    ()
  else (
    match
      expr.node
    with
    | Q.Column names ->
      let column = resolve scope expr.offset names in
      if
        List.exists scope.columns ~f:(fun local ->
          String.equal local.identity column.identity)
      then
        reject expr.offset "column must appear in GROUP BY or an aggregate"
    | Call call
      when Option.is_none call.over && is_aggregate (name_of_call expr.offset call.name)
      -> ()
    | Call { over = Some window; _ } ->
      List.iter
        (children expr @ window_expressions (resolve_window environment.windows window))
        ~f:(check_group state environment scope allowed)
    | Scalar query | Exists query ->
      ignore
        (analyze
           state
           { environment with
             outer = Some { scope with grouped = Some allowed }
           ; top = false
           ; dml = false
           }
           query
         : result)
    | In_query (inner, query, _) ->
      check_group state environment scope allowed inner;
      ignore
        (analyze
           state
           { environment with
             outer = Some { scope with grouped = Some allowed }
           ; top = false
           ; dml = false
           }
           query
         : result)
    | _ -> List.iter (children expr) ~f:(check_group state environment scope allowed))

and analyze state environment ?expected ?(defer = false) (query : Q.statement) : result =
  let environment = { environment with lateral = None; windows = [] } in
  let names = List.map query.ctes ~f:(fun cte -> cte.Q.name) in
  if List.contains_dup names ~compare:String.compare then
    reject query.offset "duplicate CTE name";
  let definitions = query.ctes in
  let rec ctes environment pending =
    match pending with
    | [] -> environment
    | _ ->
      let available cte =
        (not query.recursive)
        || List.for_all (dependencies cte.Q.query) ~f:(fun name ->
          String.equal name cte.name
          || not
               (List.exists pending ~f:(fun dependency ->
                  String.equal dependency.Q.name name)))
      in
      let cte =
        match List.find pending ~f:available with
        | Some cte -> cte
        | None -> reject query.offset "mutually recursive CTEs are unsupported"
      in
      let self = List.mem (dependencies cte.query) cte.name ~equal:String.equal in
      let columns =
        if self && query.recursive then
          recursive_cte state environment cte
        else (
          let result =
            analyze
              state
              { environment with outer = None; top = false; dml = environment.top }
              cte.query
          in
          if result.command then
            None
          else
            Some (rename cte.offset cte.columns result.columns))
      in
      let environment =
        { environment with ctes = (cte.name, columns) :: environment.ctes }
      in
      ctes
        environment
        (List.filter pending ~f:(fun other -> not (String.equal other.Q.name cte.name)))
  in
  let environment = ctes environment definitions in
  let windows =
    match query.body with
    | Q.Select select ->
      List.fold select.windows ~init:[] ~f:(fun definitions (name, window) ->
        if List.Assoc.mem definitions name ~equal:String.equal then
          reject window.Q.offset "duplicate window name";
        definitions @ [ name, resolve_window definitions window ])
    | _ -> []
  in
  let environment = { environment with windows } in
  let result, scope, select =
    match query.body with
    | Q.Select select ->
      let scope =
        Option.value_map
          select.from
          ~default:(empty_scope environment.outer)
          ~f:(relation state environment)
      in
      Option.iter select.conditions ~f:(fun expr ->
        ignore (predicate state environment scope expr : value));
      List.iter windows ~f:(fun (_, window) ->
        ignore (infer_window state environment scope window : value list));
      let columns =
        project
          state
          environment
          scope
          ?expected
          ~defer
          ~allow_window:true
          select.projection
      in
      if List.is_empty columns then
        reject query.offset "SELECT must return at least one column";
      let result = { columns; command = false } in
      result, scope, Some select
    | Set (operator, all, left, right) ->
      let env = { environment with top = false; dml = false } in
      let left_result = analyze state env ~defer:true left in
      let right_result = analyze state env ~defer:true right in
      let pairs =
        match List.zip left_result.columns right_result.columns with
        | Ok pairs -> pairs
        | Unequal_lengths ->
          reject query.offset "set operations require equal column counts"
      in
      let types =
        List.map pairs ~f:(fun (left, right) ->
          common query.offset [ native left; native right ])
      in
      let left = analyze state env ~expected:types left in
      let right = analyze state env ~expected:types right in
      let pairs =
        match List.zip left.columns right.columns with
        | Ok pairs -> pairs
        | Unequal_lengths ->
          reject query.offset "set operations require equal column counts"
      in
      let columns =
        List.map pairs ~f:(fun (left, right) ->
          let typ = common query.offset [ native left; native right ] in
          if not (all && String.equal operator "union") then
            comparable query.offset typ;
          { left with
            native = Ok typ
          ; origin = None
          ; modifier =
              (if Option.equal Int.equal left.modifier right.modifier then
                 left.modifier
               else
                 Some (-1))
          })
      in
      { columns; command = false }, empty_scope environment.outer, None
    | Nested inner ->
      let result = analyze state environment ?expected ~defer inner in
      result, empty_scope environment.outer, None
    | Insert _ | Update _ | Delete _ ->
      if not (List.is_empty query.order) then
        reject query.offset "ORDER BY requires SELECT";
      if not environment.dml then
        reject query.offset "data-modifying statement is not allowed here";
      let result, scope = dml state environment query.body in
      result, scope, None
  in
  let projected expr prefer_output =
    match expr.Q.node with
    | Number_literal n ->
      (match Int.of_string_opt n with
       | Some index when Int.(index > 0 && index <= List.length result.columns) ->
         `Output (List.nth_exn result.columns (index - 1))
       | _ -> reject expr.offset "invalid output column position")
    | Column [ name ] ->
      let output =
        List.filter result.columns ~f:(fun column -> String.equal name column.name)
      in
      let input =
        List.filter scope.columns ~f:(fun column -> String.equal name column.name)
      in
      if
        (prefer_output && not (List.is_empty output))
        || (List.is_empty input && not (List.is_empty output))
      then
        `Output (unique expr.offset ("output column: " ^ name) output)
      else
        `Expression expr
    | _ -> `Expression expr
  in
  let aggregate =
    ref
      (List.exists windows ~f:(fun (_, window) ->
         List.exists (infer_window state environment scope window) ~f:(fun value ->
           value.aggregate)))
  in
  let groups =
    match select with
    | None -> []
    | Some select ->
      let groups =
        List.map select.group ~f:(fun expr ->
          match projected expr false with
          | `Output column ->
            List.iter select.projection ~f:(function
              | Q.Field (expr, _)
                when String.equal
                       (infer state environment scope ~allow_window:true expr).key
                       column.identity ->
                if
                  (infer state environment scope ~allow_window:true expr).aggregate
                  || has_window expr
                then
                  reject expr.offset "aggregate is not allowed in GROUP BY"
              | _ -> ());
            comparable expr.Q.offset (native column);
            column.identity
          | `Expression expr ->
            let value = infer state environment scope expr in
            if value.aggregate then
              reject expr.offset "aggregate is not allowed in GROUP BY";
            comparable expr.offset (known expr.offset value);
            value.key)
      in
      List.iter select.projection ~f:(function
        | Q.All _ -> ()
        | Field (expr, _) ->
          if (infer state environment scope ~allow_window:true expr).aggregate then
            aggregate := true);
      Option.iter select.having ~f:(fun expr ->
        let result = infer state environment scope ~expected:(scalar "bool") expr in
        if not (N.equal (known expr.Q.offset result) (scalar "bool")) then
          reject expr.offset "HAVING requires bool";
        if result.aggregate then
          aggregate := true);
      if (not (List.is_empty select.group)) || Option.is_some select.having then
        aggregate := true;
      groups
  in
  List.iter query.order ~f:(fun (expr, _, _) ->
    match projected expr true with
    | `Output column -> comparable expr.Q.offset (native column)
    | `Expression expr ->
      if Option.is_none select then
        reject expr.offset "set operation ORDER BY requires an output name or position";
      let ordered = infer state environment scope ~allow_window:true expr in
      comparable expr.offset (known expr.offset ordered);
      if ordered.aggregate then
        aggregate := true;
      Option.iter select ~f:(fun select ->
        if
          select.Q.distinct
          && not
               (List.exists result.columns ~f:(fun column ->
                  String.equal column.identity ordered.key))
        then
          reject expr.offset "SELECT DISTINCT ORDER BY must occur in projection"));
  Option.iter select ~f:(fun select ->
    if select.Q.distinct then
      List.iter result.columns ~f:(fun column -> comparable query.offset (native column));
    if !aggregate then (
      List.iter windows ~f:(fun (_, window) ->
        List.iter
          (window_expressions window)
          ~f:(check_group state environment scope groups));
      List.iter select.projection ~f:(function
        | Q.Field (expr, _) -> check_group state environment scope groups expr
        | All reference ->
          let columns =
            if List.is_empty reference.names then
              scope.columns
            else
              (unique
                 reference.offset
                 "table qualifier"
                 (List.filter scope.bindings ~f:(fun b -> matches b reference.names)))
                .columns
          in
          List.iter columns ~f:(fun column ->
            if not (List.mem groups column.identity ~equal:String.equal) then
              reject reference.offset "wildcard column must appear in GROUP BY"));
      Option.iter select.having ~f:(check_group state environment scope groups);
      List.iter query.order ~f:(fun (expr, _, _) ->
        match projected expr true with
        | `Output _ -> ()
        | `Expression expr -> check_group state environment scope groups expr)));
  if
    result.command
    && ((not (List.is_empty query.order))
        || Option.is_some query.limit
        || Option.is_some query.pagination_offset)
  then
    reject query.offset "pagination and ORDER BY require SELECT";
  (match query.body with
   | (Q.Insert _ | Update _ | Delete _)
     when Option.is_some query.limit || Option.is_some query.pagination_offset ->
     reject query.offset "pagination requires SELECT"
   | _ -> ());
  List.iter
    (Option.to_list query.limit @ Option.to_list query.pagination_offset)
    ~f:(fun expr ->
      (match expr.Q.node with
       | Number_literal text when Option.is_none (Int64.of_string_opt text) ->
         reject expr.offset "pagination requires an int64 integer literal"
       | Column _ -> reject expr.offset "pagination cannot refer to a column"
       | _ -> ());
      let value =
        infer state environment (empty_scope None) ~expected:(scalar "int8") expr
      in
      if
        not
          (List.exists
             [ scalar "int2"; scalar "int4"; scalar "int8" ]
             ~f:(N.equal (known expr.Q.offset value)))
      then
        reject expr.offset "pagination requires an integer or parameter");
  result

and recursive_cte state environment (cte : Q.cte) =
  if
    Option.is_some cte.query.limit
    || Option.is_some cte.query.pagination_offset
    || (not (List.is_empty cte.query.order))
    || not (List.is_empty cte.query.ctes)
  then
    reject cte.offset "unsupported recursive CTE decoration";
  let all, anchor, term =
    match cte.query.body with
    | Q.Set ("union", all, anchor, term) -> all, anchor, term
    | _ -> reject cte.offset "recursive CTE requires anchor UNION [ALL] recursive term"
  in
  if List.mem (dependencies anchor) cte.name ~equal:String.equal then
    reject cte.offset "recursive reference is not allowed in the anchor";
  if
    (not (List.is_empty term.Q.order))
    || Option.is_some term.limit
    || Option.is_some term.pagination_offset
    || not (List.is_empty term.ctes)
  then
    reject term.offset "unsupported recursive term decoration";
  let anchor =
    analyze state { environment with outer = None; top = false; dml = false } anchor
  in
  if not all then
    List.iter anchor.columns ~f:(fun column -> comparable cte.offset (native column));
  let columns =
    rename cte.offset cte.columns anchor.columns
    |> List.map ~f:(fun (column : column) -> { column with origin = None })
  in
  let rec select_term (query : Q.statement) =
    match query.body with
    | Q.Nested inner ->
      if
        (not (List.is_empty query.order))
        || Option.is_some query.limit
        || Option.is_some query.pagination_offset
        || not (List.is_empty query.ctes)
      then
        reject query.offset "unsupported recursive term decoration";
      select_term inner
    | Q.Select select
      when List.is_empty select.group
           && Option.is_none select.having
           && not select.distinct -> select
    | _ -> reject cte.offset "recursive term requires a non-aggregate SELECT"
  in
  let select = select_term term in
  let rec check_source nullable (source : Q.relation) =
    match source.relation with
    | Q.Table { names = [ name ]; _ } when String.equal name cte.name ->
      if nullable then
        reject
          source.offset
          "recursive reference cannot occur on the nullable side of an outer join";
      1
    | Table _ -> 0
    | Derived query | Lateral query ->
      if List.mem (dependencies query) cte.name ~equal:String.equal then
        reject source.offset "recursive reference inside a subquery is unsupported";
      0
    | Join (left, right, kind, condition) ->
      let extra =
        match condition with
        | Q.On expr -> expression_dependencies expr
        | _ -> []
      in
      if List.mem extra cte.name ~equal:String.equal then
        reject source.offset "recursive reference in JOIN subquery is unsupported";
      check_source
        (nullable
         ||
         match kind with
         | Q.Right | Full -> true
         | _ -> false)
        left
      + check_source
          (nullable
           ||
           match kind with
           | Q.Left | Full -> true
           | _ -> false)
          right
  in
  let count = Option.value_map select.from ~default:0 ~f:(check_source false) in
  if not (Int.equal count 1) then
    reject cte.offset "recursive term requires exactly one self-reference";
  let expressions =
    List.filter_map select.projection ~f:(function
      | Q.Field (expr, _) -> Some expr
      | _ -> None)
    @ Option.to_list select.conditions
  in
  let rec aggregated (expr : Q.expression) =
    match expr.node with
    | Call call when is_aggregate (name_of_call expr.offset call.name) -> true
    | Scalar _ | Exists _ -> false
    | _ -> List.exists (children expr) ~f:aggregated
  in
  List.iter expressions ~f:(fun expr ->
    if aggregated expr then
      reject expr.Q.offset "aggregate is not allowed in recursive term";
    if List.mem (expression_dependencies expr) cte.name ~equal:String.equal then
      reject expr.Q.offset "recursive reference inside a subquery is unsupported");
  let environment =
    { ctes = (cte.name, Some columns) :: environment.ctes
    ; outer = None
    ; top = false
    ; dml = false
    ; lateral = None
    ; windows = []
    }
  in
  let term_result = analyze state environment term in
  let pairs =
    match List.zip columns term_result.columns with
    | Ok pairs -> pairs
    | Unequal_lengths -> reject cte.offset "recursive term has incompatible column count"
  in
  List.iter pairs ~f:(fun (a, b) ->
    if not (N.equal (native a) (native b)) then
      reject cte.offset "recursive term type differs from anchor; add explicit casts");
  Some columns

and dml state environment body =
  let target, alias =
    match body with
    | Q.Insert (target, alias, _, _, _, _, _)
    | Update (target, alias, _, _, _, _)
    | Delete (target, alias, _, _, _) -> target, alias
    | _ -> reject 0 "DML analyzer received a SELECT"
  in
  let target_table = table state target.offset target.names in
  let source : Q.relation =
    { relation = Table target; alias; columns = []; offset = target.offset }
  in
  let scope = relation state { environment with ctes = []; outer = None } source in
  let resolve_target (reference : Q.reference) =
    match reference.names with
    | [ name ] ->
      unique
        reference.offset
        ("target column: " ^ name)
        (List.filter scope.columns ~f:(fun c -> String.equal c.name name))
    | _ -> reject reference.offset "expected =; target column must be unqualified"
  in
  let sources =
    match body with
    | Q.Update (_, _, _, sources, _, _) | Delete (_, _, sources, _, _) -> sources
    | _ -> None
  in
  let scope =
    match sources with
    | None -> scope
    | Some source ->
      let extra = relation state { environment with lateral = None } source in
      { scope with
        bindings = merge_bindings source.offset scope.bindings extra.bindings
      ; columns = scope.columns @ extra.columns
      }
  in
  let assigned expression_scope seen (reference, expr) =
    let column = resolve_target reference in
    if List.mem seen column.name ~equal:String.equal then
      reject reference.offset "duplicate target column";
    (match expr.Q.node with
     | Q.Default -> ()
     | _ ->
       let result =
         infer state environment expression_scope ~expected:(native column) expr
       in
       let actual = known expr.offset result in
       if result.aggregate then
         reject expr.offset "aggregate is not allowed in assigned values";
       if
         not
           (N.implicit actual (native column)
            || (N.numeric actual && N.numeric (native column)))
       then
         reject expr.offset "incompatible assigned PostgreSQL type");
    column.name :: seen
  in
  let returning =
    match body with
    | Q.Update (_, _, assignments, _, condition, returning) ->
      ignore (List.fold assignments ~init:[] ~f:(assigned scope) : string list);
      Option.iter condition ~f:(fun expr ->
        ignore (predicate state environment scope expr : value));
      returning
    | Delete (_, _, _, condition, returning) ->
      Option.iter condition ~f:(fun expr ->
        ignore (predicate state environment scope expr : value));
      returning
    | Insert (_, _, columns, rows, input, conflict, returning) ->
      let columns =
        if List.is_empty columns && Option.is_some input then
          List.map scope.columns ~f:(fun column ->
            { Q.names = [ column.name ]; offset = target.offset })
        else
          columns
      in
      let targets = List.map columns ~f:resolve_target in
      if List.contains_dup (List.map targets ~f:(fun c -> c.name)) ~compare:String.compare
      then
        reject target.offset "duplicate target column";
      Option.iter rows ~f:(fun rows ->
        List.iter rows ~f:(fun row ->
          let pairs =
            match List.zip columns row with
            | Ok pairs -> pairs
            | Unequal_lengths ->
              reject target.offset "VALUES row length does not match INSERT columns"
          in
          ignore (List.fold pairs ~init:[] ~f:(assigned (empty_scope None)) : string list)));
      Option.iter input ~f:(fun query ->
        let result =
          analyze
            state
            { environment with top = false; dml = false }
            ~expected:(List.map targets ~f:native)
            query
        in
        let pairs =
          match List.zip targets result.columns with
          | Ok pairs -> pairs
          | Unequal_lengths ->
            reject query.Q.offset "INSERT SELECT column count does not match target"
        in
        List.iter pairs ~f:(fun (a, b) ->
          if
            not
              (N.implicit (native b) (native a)
               || (N.numeric (native a) && N.numeric (native b)))
          then
            reject query.offset "incompatible INSERT SELECT column types"));
      Option.iter conflict ~f:(fun conflict ->
        Option.iter conflict.Q.target ~f:(fun targets ->
          let names =
            List.map targets ~f:(fun r -> (resolve_target r).name)
            |> List.sort ~compare:String.compare
          in
          let primary =
            List.filter (S.columns target_table) ~f:(fun c ->
              Option.is_some (S.column_primary_key_position c))
            |> List.map ~f:(fun c -> I.to_string (S.column_name c))
          in
          let keys =
            primary
            :: List.map (S.unique_constraints target_table) ~f:(fun k ->
              List.map (S.unique_constraint_columns k) ~f:I.to_string)
          in
          if
            List.is_empty names
            || not
                 (List.exists keys ~f:(fun key ->
                    List.equal String.equal names (List.sort key ~compare:String.compare)))
          then
            reject
              target.offset
              "conflict columns do not match a primary or unique key in the snapshot");
        match conflict.action with
        | Do_nothing -> ()
        | Do_update (assignments, condition) ->
          if Option.value_map alias ~default:false ~f:(String.equal "excluded") then
            reject
              target.offset
              "ON CONFLICT DO UPDATE requires a target alias other than excluded";
          if Option.is_none conflict.target then
            reject target.offset "ON CONFLICT DO UPDATE requires conflict columns";
          let excluded =
            { names = [ "excluded" ]; alias = true; columns = scope.columns }
          in
          let scope = { scope with bindings = scope.bindings @ [ excluded ] } in
          let assigned =
            List.fold assignments ~init:[] ~f:(fun seen (r, e) ->
              let column = resolve_target r in
              if List.mem seen column.name ~equal:String.equal then
                reject r.Q.offset "duplicate target column";
              (match e.Q.node with
               | Default -> ()
               | _ ->
                 let result = infer state environment scope ~expected:(native column) e in
                 if result.aggregate then
                   reject e.offset "aggregate is not allowed in assigned values";
                 let actual = known e.offset result in
                 if
                   not
                     (N.implicit actual (native column)
                      || (N.numeric actual && N.numeric (native column)))
                 then
                   reject e.offset "incompatible assigned PostgreSQL type");
              column.name :: seen)
          in
          ignore (assigned : string list);
          Option.iter condition ~f:(fun e ->
            ignore (predicate state environment scope e : value)));
      returning
    | _ -> reject target.offset "DML analyzer lost its statement kind"
  in
  List.iter returning ~f:(function
    | Q.Field (expr, _)
      when (infer state environment scope ~allow_window:true expr).aggregate ->
      reject expr.offset "aggregate is not allowed in RETURNING"
    | _ -> ());
  ( { columns = project state environment scope returning
    ; command = List.is_empty returning
    }
  , scope )
;;

let create schema query =
  let state = { schema; next = 0; parameters = [] } in
  try
    let result =
      analyze
        state
        { ctes = []; outer = None; top = true; dml = true; lateral = None; windows = [] }
        query
    in
    let fields =
      List.map result.columns ~f:(fun column ->
        { name = column.name
        ; codec = N.codec (native column)
        ; nullable = origin_nullable column
        })
    in
    let parameters =
      List.sort state.parameters ~compare:(fun (a, _) (b, _) ->
        Int.compare a.Q.start b.Q.start)
      |> List.map ~f:(fun (value, typ) -> { value; codec = N.codec typ })
    in
    Ok { fields; parameters }
  with
  | Invalid error -> Error error
;;
