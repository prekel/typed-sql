open! Base

type error = Sql_query.error =
  { offset : int
  ; message : string
  }

type reference = Sql_query.reference =
  { names : string list
  ; offset : int
  }

type parameter = Sql_query.parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type operand =
  | Reference of reference
  | Parameter_value of parameter
  | String_literal of string * int
  | Number_literal of string * int
  | Bool_literal of bool * int
  | Null_literal of int

type predicate =
  | Boolean of operand
  | Compare of string * operand * operand
  | Is_null of operand * bool
  | Like of operand * operand * bool * bool * operand option
  | Between of operand * operand * operand * bool
  | In of operand * operand list * bool
  | Quantified of string * operand * operand * bool
  | Not of predicate
  | And of predicate * predicate
  | Or of predicate * predicate

type projection =
  | Column of reference * string option
  | All of reference

type value =
  | Bind of parameter
  | Default of int
  | Excluded of reference

type assignment = reference * value

type conflict_action =
  | Do_nothing
  | Do_update of assignment list * predicate option

type conflict =
  { target : reference list option
  ; action : conflict_action
  }

type statement =
  | Select
  | Insert of
      { columns : reference list
      ; rows : value list list option
      ; conflict : conflict option
      }
  | Update of assignment list
  | Delete

type relation =
  { schema : string
  ; table : string
  ; alias : string option
  ; offset : int
  }

type join =
  { relation : relation
  ; condition : predicate
  }

type t =
  { source : string
  ; extended : Sql_query.statement option
  ; schema : string
  ; table : string
  ; alias : string option
  ; statement : statement
  ; joins : join list
  ; projection : projection list
  ; conditions : predicate option
  ; limit : operand option
  ; offset : operand option
  ; order : reference list
  }

type kind = Sql_query.kind =
  | Word of string
  | Quoted of string
  | Symbol of char
  | Parameter of parameter
  | String_sql of string
  | Number of string
  | Operator of string
  | End

type token = Sql_query.token =
  { kind : kind
  ; offset : int
  }

let error_to_string { offset; message } =
  "SQL byte " ^ Int.to_string offset ^ ": " ^ message
;;

let fail offset message = Error { offset; message }

let reserved =
  [ "select"
  ; "from"
  ; "where"
  ; "and"
  ; "order"
  ; "by"
  ; "as"
  ; "asc"
  ; "desc"
  ; "distinct"
  ; "join"
  ; "natural"
  ; "left"
  ; "right"
  ; "inner"
  ; "outer"
  ; "cross"
  ; "full"
  ; "limit"
  ; "offset"
  ; "group"
  ; "having"
  ; "union"
  ; "intersect"
  ; "except"
  ; "or"
  ; "on"
  ; "null"
  ; "true"
  ; "false"
  ; "for"
  ; "fetch"
  ; "using"
  ; "insert"
  ; "into"
  ; "values"
  ; "update"
  ; "set"
  ; "delete"
  ; "returning"
  ; "default"
  ; "conflict"
  ; "do"
  ; "nothing"
  ; "constraint"
  ; "not"
  ; "is"
  ; "like"
  ; "ilike"
  ; "between"
  ; "in"
  ; "any"
  ; "all"
  ; "escape"
  ; "overriding"
  ]
;;

let lex = Sql_query.lex

let position = function
  | [] -> 0
  | token :: _ -> token.offset
;;

let keyword name = function
  | { kind = Word word; _ } :: rest when String.equal name word -> Some rest
  | _ -> None
;;

let symbol character = function
  | { kind = Symbol actual; _ } :: rest when Char.equal character actual -> Some rest
  | _ -> None
;;

let expect_keyword name tokens =
  match keyword name tokens with
  | Some rest -> Ok rest
  | None -> fail (position tokens) ("expected " ^ String.uppercase name)
;;

let expect_symbol character tokens =
  match symbol character tokens with
  | Some rest -> Ok rest
  | None -> fail (position tokens) ("expected " ^ String.of_char character)
;;

let identifier = function
  | { kind = Quoted name; _ } :: rest -> Ok (name, rest)
  | { kind = Word name; _ } :: rest when not (List.mem reserved name ~equal:String.equal)
    -> Ok (name, rest)
  | tokens -> fail (position tokens) "expected SQL identifier"
;;

let reference ~star tokens =
  let start = position tokens in
  let rec names acc tokens =
    let open Result.Let_syntax in
    match
      if star then
        symbol '*' tokens
      else
        None
    with
    | Some rest -> Ok ({ names = List.rev acc; offset = start }, true, rest)
    | None ->
      let%bind name, rest = identifier tokens in
      let acc = name :: acc in
      (match symbol '.' rest with
       | Some rest -> names acc rest
       | None -> Ok ({ names = List.rev acc; offset = start }, false, rest))
  in
  names [] tokens
;;

let comma_list parse_item tokens =
  let open Result.Let_syntax in
  let rec loop acc tokens =
    let%bind item, rest = parse_item tokens in
    match symbol ',' rest with
    | Some rest -> loop (item :: acc) rest
    | None -> Ok (List.rev (item :: acc), rest)
  in
  loop [] tokens
;;

let column_name tokens =
  let offset = position tokens in
  let open Result.Let_syntax in
  let%map name, rest = identifier tokens in
  { names = [ name ]; offset }, rest
;;

let projection tokens =
  let open Result.Let_syntax in
  comma_list
    (fun tokens ->
       let%bind field, all, rest = reference ~star:true tokens in
       if all then
         Ok (All field, rest)
       else (
         match
           keyword "as" rest
         with
         | None -> Ok (Column (field, None), rest)
         | Some rest ->
           let%map alias, rest = identifier rest in
           Column (field, Some alias), rest))
    tokens
;;

let table_source ~bare_alias tokens =
  let open Result.Let_syntax in
  let%bind table_ref, _, tokens = reference ~star:false tokens in
  let%bind schema, table =
    match table_ref.names with
    | [ table ] -> Ok ("public", table)
    | [ schema; table ] -> Ok (schema, table)
    | _ -> fail table_ref.offset "expected table or schema.table"
  in
  let%map alias, tokens =
    match keyword "as" tokens with
    | Some rest ->
      let%map alias, rest = identifier rest in
      Some alias, rest
    | None ->
      (match tokens with
       | { kind = Quoted _; _ } :: _ when bare_alias ->
         let%map alias, rest = identifier tokens in
         Some alias, rest
       | { kind = Word name; _ } :: _
         when bare_alias && not (List.mem reserved name ~equal:String.equal) ->
         let%map alias, rest = identifier tokens in
         Some alias, rest
       | _ -> Ok (None, tokens))
  in
  (schema, table, alias), tokens
;;

let operand tokens =
  let open Result.Let_syntax in
  match tokens with
  | { kind = Parameter parameter; _ } :: rest -> Ok (Parameter_value parameter, rest)
  | { kind = String_sql value; offset } :: rest ->
    Ok (String_literal (value, offset), rest)
  | { kind = Number value; offset } :: rest -> Ok (Number_literal (value, offset), rest)
  | { kind = Word "true"; offset } :: rest -> Ok (Bool_literal (true, offset), rest)
  | { kind = Word "false"; offset } :: rest -> Ok (Bool_literal (false, offset), rest)
  | { kind = Word "null"; offset } :: rest -> Ok (Null_literal offset, rest)
  | _ ->
    let%map reference, _, rest = reference ~star:false tokens in
    Reference reference, rest
;;

let comparison = function
  | { kind = Symbol '='; _ } :: rest -> Some ("=", rest)
  | { kind = Operator operator; _ } :: rest -> Some (operator, rest)
  | _ -> None
;;

let rec disjunction tokens =
  let open Result.Let_syntax in
  let%bind left, rest = conjunction tokens in
  let rec loop left rest =
    match keyword "or" rest with
    | None -> Ok (left, rest)
    | Some rest ->
      let%bind right, rest = conjunction rest in
      loop (Or (left, right)) rest
  in
  loop left rest

and conjunction tokens =
  let open Result.Let_syntax in
  let%bind left, rest = negation tokens in
  let rec loop left rest =
    match keyword "and" rest with
    | None -> Ok (left, rest)
    | Some rest ->
      let%bind right, rest = negation rest in
      loop (And (left, right)) rest
  in
  loop left rest

and negation tokens =
  let open Result.Let_syntax in
  match keyword "not" tokens with
  | Some rest ->
    let%map value, rest = negation rest in
    Not value, rest
  | None ->
    (match symbol '(' tokens with
     | Some rest ->
       let%bind value, rest = disjunction rest in
       let%map rest = expect_symbol ')' rest in
       value, rest
     | None -> predicate tokens)

and predicate tokens =
  let open Result.Let_syntax in
  let%bind left, rest = operand tokens in
  match comparison rest with
  | Some (operator, rest) ->
    (match rest with
     | { kind = Word quantifier; _ } :: rest
       when String.equal quantifier "any" || String.equal quantifier "all" ->
       let%bind rest = expect_symbol '(' rest in
       let%bind right, rest = operand rest in
       let%map rest = expect_symbol ')' rest in
       Quantified (operator, left, right, String.equal quantifier "any"), rest
     | _ ->
       let%map right, rest = operand rest in
       Compare (operator, left, right), rest)
  | None ->
    (match keyword "is" rest with
     | Some rest ->
       let not_null, rest =
         match keyword "not" rest with
         | None -> false, rest
         | Some rest -> true, rest
       in
       let%map rest = expect_keyword "null" rest in
       Is_null (left, not_null), rest
     | None ->
       let negative, remaining =
         match keyword "not" rest with
         | None -> false, rest
         | Some rest -> true, rest
       in
       (match remaining with
        | { kind = Word name; _ } :: rest
          when String.equal name "like" || String.equal name "ilike" ->
          let%bind right, rest = operand rest in
          let%map escape, rest =
            match keyword "escape" rest with
            | None -> Ok (None, rest)
            | Some rest ->
              let%map value, rest = operand rest in
              Some value, rest
          in
          Like (left, right, negative, String.equal name "ilike", escape), rest
        | { kind = Word "between"; _ } :: rest ->
          let%bind low, rest = operand rest in
          let%bind rest = expect_keyword "and" rest in
          let%map high, rest = operand rest in
          Between (left, low, high, negative), rest
        | { kind = Word "in"; _ } :: rest ->
          let%bind rest = expect_symbol '(' rest in
          let%bind values, rest = comma_list operand rest in
          let%map rest = expect_symbol ')' rest in
          In (left, values, negative), rest
        | _ when negative ->
          fail (position remaining) "expected LIKE, ILIKE, BETWEEN or IN after NOT"
        | _ -> Ok (Boolean left, rest)))
;;

let where tokens =
  let open Result.Let_syntax in
  match keyword "where" tokens with
  | None -> Ok (None, tokens)
  | Some rest ->
    let%map value, rest = disjunction rest in
    Some value, rest
;;

let joins tokens =
  let open Result.Let_syntax in
  let rec loop acc tokens =
    let%bind remaining =
      match keyword "inner" tokens with
      | Some rest ->
        let%map rest = expect_keyword "join" rest in
        Some rest
      | None -> Ok (keyword "join" tokens)
    in
    match remaining with
    | None -> Ok (List.rev acc, tokens)
    | Some rest ->
      let offset = position rest in
      let%bind (schema, table, alias), rest = table_source ~bare_alias:true rest in
      let%bind rest = expect_keyword "on" rest in
      let%bind condition, rest = disjunction rest in
      loop ({ relation = { schema; table; alias; offset }; condition } :: acc) rest
  in
  loop [] tokens
;;

let pagination tokens =
  let open Result.Let_syntax in
  let rec loop limit offset tokens =
    match tokens with
    | { kind = Word name; offset = position } :: rest
      when String.equal name "limit" || String.equal name "offset" ->
      let is_limit = String.equal name "limit" in
      if (is_limit && Option.is_some limit) || ((not is_limit) && Option.is_some offset)
      then
        fail position "duplicate pagination clause"
      else (
        let%bind value, rest =
          match rest with
          | { kind = Word "all"; offset } :: rest when is_limit ->
            Ok (Null_literal offset, rest)
          | _ -> operand rest
        in
        match value with
        | Number_literal (number, pos) when Option.is_none (Int64.of_string_opt number) ->
          fail pos "pagination requires an int64 integer literal"
        | Reference reference ->
          fail reference.offset "pagination cannot refer to a column"
        | String_literal (_, pos) | Bool_literal (_, pos) ->
          fail pos "pagination requires an integer or parameter"
        | _ ->
          loop
            (if is_limit then
               Some value
             else
               limit)
            (if is_limit then
               offset
             else
               Some value)
            rest)
    | _ -> Ok (limit, offset, tokens)
  in
  loop None None tokens
;;

let returning tokens =
  match keyword "returning" tokens with
  | None -> Ok ([], tokens)
  | Some rest -> projection rest
;;

let value ~excluded tokens =
  let open Result.Let_syntax in
  match tokens with
  | { kind = Parameter parameter; _ } :: rest -> Ok (Bind parameter, rest)
  | { kind = Word name; offset } :: rest when String.equal name "default" ->
    Ok (Default offset, rest)
  | _ when excluded ->
    let%bind column, _, rest = reference ~star:false tokens in
    (match column.names with
     | [ "excluded"; _ ] -> Ok (Excluded column, rest)
     | _ -> fail column.offset "expected parameter, DEFAULT or EXCLUDED.column")
  | _ -> fail (position tokens) "expected an OCaml bind parameter or DEFAULT"
;;

let assignments ~excluded tokens =
  let open Result.Let_syntax in
  comma_list
    (fun tokens ->
       let%bind column, rest = column_name tokens in
       let%bind rest = expect_symbol '=' rest in
       let%map value, rest = value ~excluded rest in
       (column, value), rest)
    tokens
;;

let conflict tokens =
  let open Result.Let_syntax in
  match keyword "on" tokens with
  | None -> Ok (None, tokens)
  | Some rest ->
    let%bind rest = expect_keyword "conflict" rest in
    let%bind target, rest =
      match symbol '(' rest with
      | None -> Ok (None, rest)
      | Some rest ->
        let%bind columns, rest = comma_list column_name rest in
        let%map rest = expect_symbol ')' rest in
        Some columns, rest
    in
    let%bind rest = expect_keyword "do" rest in
    let%map action, rest =
      match keyword "nothing" rest with
      | Some rest -> Ok (Do_nothing, rest)
      | None ->
        let%bind rest = expect_keyword "update" rest in
        let%bind rest = expect_keyword "set" rest in
        let%bind values, rest = assignments ~excluded:true rest in
        let%map conditions, rest = where rest in
        Do_update (values, conditions), rest
    in
    Some { target; action }, rest
;;

let parse_legacy source =
  let open Result.Let_syntax in
  let%bind tokens = lex source in
  let%bind (schema, table, alias), statement, joins, projection, conditions, order, tokens
    =
    match tokens with
    | { kind = Word name; _ } :: rest when String.equal name "select" ->
      let%bind fields, rest = projection rest in
      let%bind rest = expect_keyword "from" rest in
      let%bind table, rest = table_source ~bare_alias:true rest in
      let%bind joins, rest = joins rest in
      let%bind conditions, rest = where rest in
      let%map order, rest =
        match keyword "order" rest with
        | None -> Ok ([], rest)
        | Some rest ->
          let%bind rest = expect_keyword "by" rest in
          comma_list
            (fun tokens ->
               let%map column, _, rest = reference ~star:false tokens in
               let rest =
                 match keyword "asc" rest with
                 | Some rest -> rest
                 | None -> Option.value (keyword "desc" rest) ~default:rest
               in
               column, rest)
            rest
      in
      table, Select, joins, fields, conditions, order, rest
    | { kind = Word name; _ } :: rest when String.equal name "insert" ->
      let%bind rest = expect_keyword "into" rest in
      let%bind table, rest = table_source ~bare_alias:false rest in
      let%bind columns, rest =
        match symbol '(' rest with
        | None -> Ok ([], rest)
        | Some rest ->
          let%bind columns, rest = comma_list column_name rest in
          let%map rest = expect_symbol ')' rest in
          columns, rest
      in
      let%bind rows, rest =
        match keyword "default" rest with
        | Some rest ->
          let%map rest = expect_keyword "values" rest in
          None, rest
        | None ->
          let%bind rest = expect_keyword "values" rest in
          let%map rows, rest =
            comma_list
              (fun tokens ->
                 let%bind rest = expect_symbol '(' tokens in
                 let%bind values, rest = comma_list (value ~excluded:false) rest in
                 let%map rest = expect_symbol ')' rest in
                 values, rest)
              rest
          in
          Some rows, rest
      in
      let%bind conflict, rest = conflict rest in
      let%map fields, rest = returning rest in
      table, Insert { columns; rows; conflict }, [], fields, None, [], rest
    | { kind = Word name; _ } :: rest when String.equal name "update" ->
      let%bind table, rest = table_source ~bare_alias:true rest in
      let%bind rest = expect_keyword "set" rest in
      let%bind values, rest = assignments ~excluded:false rest in
      let%bind conditions, rest = where rest in
      let%map fields, rest = returning rest in
      table, Update values, [], fields, conditions, [], rest
    | { kind = Word name; _ } :: rest when String.equal name "delete" ->
      let%bind rest = expect_keyword "from" rest in
      let%bind table, rest = table_source ~bare_alias:true rest in
      let%bind conditions, rest = where rest in
      let%map fields, rest = returning rest in
      table, Delete, [], fields, conditions, [], rest
    | _ -> fail (position tokens) "expected SELECT, INSERT, UPDATE or DELETE"
  in
  let%bind limit, offset, tokens =
    match statement with
    | Select -> pagination tokens
    | Insert _ | Update _ | Delete -> Ok (None, None, tokens)
  in
  let tokens = Option.value (symbol ';' tokens) ~default:tokens in
  match tokens with
  | [ { kind = End; _ } ] ->
    Ok
      { source
      ; extended = None
      ; schema
      ; table
      ; alias
      ; statement
      ; joins
      ; projection
      ; conditions
      ; limit
      ; offset
      ; order
      }
  | token :: _ -> fail token.offset "unsupported trailing SQL; expected end of statement"
  | [] -> fail (String.length source) "SQL parser lost its end-of-input marker"
;;

let parse source =
  match parse_legacy source with
  | Ok query -> Ok query
  | Error legacy_error ->
    let open Result.Let_syntax in
    let%bind tokens = lex source in
    (match Sql_query.parse tokens with
     | Error extended_error ->
       let extended =
         List.exists tokens ~f:(fun token ->
           match token.kind with
           | Word name ->
             List.mem
               [ "with"
               ; "recursive"
               ; "case"
               ; "cast"
               ; "group"
               ; "having"
               ; "union"
               ; "intersect"
               ; "except"
               ; "left"
               ; "right"
               ; "full"
               ; "cross"
               ; "natural"
               ; "using"
               ]
               name
               ~equal:String.equal
           | Operator "::" -> true
           | _ -> false)
       in
       Error
         (if extended then
            extended_error
          else
            legacy_error)
     | Ok extended ->
       Ok
         { source
         ; extended = Some extended
         ; schema = "public"
         ; table = ""
         ; alias = None
         ; statement = Select
         ; joins = []
         ; projection = []
         ; conditions = None
         ; limit = None
         ; offset = None
         ; order = []
         })
;;
