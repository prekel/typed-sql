open! Base

type error =
  { offset : int
  ; message : string
  }

type reference =
  { names : string list
  ; offset : int
  }

type parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type kind =
  | Word of string
  | Quoted of string
  | Symbol of char
  | Parameter of parameter
  | String_sql of string
  | Number of string
  | Operator of string
  | End

type token =
  { kind : kind
  ; offset : int
  }

let fail offset message = Error { offset; message }
let word_start c = Char.is_alpha c || Char.equal c '_' || Int.(Char.to_int c >= 128)
let word_char c = word_start c || Char.is_digit c || Char.equal c '$'
let ocaml_name_char c = Char.is_alphanum c || Char.equal c '_' || Char.equal c '\''

let valid_expression source =
  match
    Result.try_with (fun () -> Ppxlib.Parse.expression (Stdlib.Lexing.from_string source))
  with
  | Ok _ -> true
  | Error _ -> false
;;

let lex source =
  let length = String.length source in
  let has i text =
    let n = String.length text in
    Int.(i + n <= length) && String.equal (String.sub source ~pos:i ~len:n) text
  in
  let rec comment start depth i =
    if Int.(i >= length) then
      fail start "unterminated block comment"
    else if has i "/*" then
      comment start (depth + 1) (i + 2)
    else if has i "*/" then
      if Int.(depth = 1) then
        Ok (i + 2)
      else
        comment start (depth - 1) (i + 2)
    else
      comment start depth (i + 1)
  in
  let rec quoted start i acc =
    if Int.(i >= length) then
      fail start "unterminated quoted identifier"
    else if has i "\"\"" then
      quoted start (i + 2) ('"' :: acc)
    else if Char.equal source.[i] '"' then (
      let name = String.of_char_list (List.rev acc) in
      if String.is_empty name then
        fail start "empty quoted identifier"
      else
        Ok (name, i + 1))
    else
      quoted start (i + 1) (source.[i] :: acc)
  in
  let number start =
    let digits i =
      let rec loop i =
        if Int.(i < length) && Char.is_digit source.[i] then
          loop (i + 1)
        else
          i
      in
      loop i
    in
    let i =
      if has start "+" || has start "-" then
        start + 1
      else
        start
    in
    let i = digits i in
    let i =
      if has i "." then
        digits (i + 1)
      else
        i
    in
    let open Result.Let_syntax in
    let%map stop =
      if has i "e" || has i "E" then (
        let exponent =
          if has (i + 1) "+" || has (i + 1) "-" then
            i + 2
          else
            i + 1
        in
        let stop = digits exponent in
        if Int.(stop = exponent) then
          fail start "invalid numeric literal exponent"
        else
          Ok stop)
      else
        Ok i
    in
    String.sub source ~pos:start ~len:(stop - start), stop
  in
  let rec embedded start expression_start i =
    if Int.(i >= length) then
      fail start "unterminated or invalid OCaml parameter expression"
    else if Char.equal source.[i] '}' then (
      let expression =
        String.sub source ~pos:expression_start ~len:(i - expression_start)
      in
      if valid_expression expression then
        Ok (expression, i + 1)
      else
        embedded start expression_start (i + 1))
    else
      embedded start expression_start (i + 1)
  in
  let rec scan i acc =
    let open Result.Let_syntax in
    if Int.(i >= length) then
      Ok (List.rev ({ kind = End; offset = length } :: acc))
    else if Char.is_whitespace source.[i] then
      scan (i + 1) acc
    else if has i "--" then (
      let stop = String.index_from source (i + 2) '\n' |> Option.value ~default:length in
      scan stop acc)
    else if has i "/*" then (
      let%bind stop = comment i 1 (i + 2) in
      scan stop acc)
    else if Char.equal source.[i] '\'' || has i "E'" || has i "e'" then (
      let escape = not (Char.equal source.[i] '\'') in
      let%bind value, stop =
        Sql_string.quoted
          ~escape
          source
          ~quote:
            (if escape then
               i + 1
             else
               i)
        |> Result.map_error ~f:(fun (e : Sql_string.error) ->
          { offset = e.offset; message = e.message })
      in
      scan stop ({ kind = String_sql value; offset = i } :: acc))
    else if List.exists [ "->>"; "#>>"; "->"; "#>" ] ~f:(has i) then (
      let op = List.find_exn [ "->>"; "#>>"; "->"; "#>" ] ~f:(has i) in
      scan (i + String.length op) ({ kind = Operator op; offset = i } :: acc))
    else if
      Char.is_digit source.[i]
      || (List.mem [ '+'; '-'; '.' ] source.[i] ~equal:Char.equal
          && (match acc with
              | { kind = Number _ | Parameter _ | Quoted _ | String_sql _ | Symbol ')'
                ; _
                }
                :: _ -> false
              | { kind = Word name; _ } :: _ ->
                List.mem
                  [ "limit"
                  ; "offset"
                  ; "then"
                  ; "else"
                  ; "select"
                  ; "where"
                  ; "and"
                  ; "or"
                  ; "between"
                  ; "by"
                  ; "when"
                  ; "returning"
                  ]
                  name
                  ~equal:String.equal
              | _ -> true)
          && Int.(i + 1 < length)
          && (Char.is_digit source.[i + 1]
              || ((not (Char.equal source.[i] '.'))
                  && has (i + 1) "."
                  && Int.(i + 2 < length)
                  && Char.is_digit source.[i + 2])))
    then (
      let%bind value, stop = number i in
      scan stop ({ kind = Number value; offset = i } :: acc))
    else if Char.equal source.[i] '"' then (
      let%bind name, stop = quoted i (i + 1) [] in
      scan stop ({ kind = Quoted name; offset = i } :: acc))
    else if
      Char.equal source.[i] '$' && Option.is_some (Sql_string.dollar_opener source i)
    then (
      let delimiter, body = Option.value_exn (Sql_string.dollar_opener source i) in
      let%bind value, stop =
        Sql_string.dollar source ~start:i ~delimiter ~body
        |> Result.map_error ~f:(fun (e : Sql_string.error) ->
          { offset = e.offset; message = e.message })
      in
      scan stop ({ kind = String_sql value; offset = i } :: acc))
    else if Char.equal source.[i] '$' then (
      let%bind () =
        if has (i + 1) "@" then
          fail i "list substitutions are deferred; only static SQL shapes are supported"
        else
          Ok ()
      in
      let optional = has (i + 1) "?" in
      let start =
        i
        +
        if optional then
          2
        else
          1
      in
      let%bind expression, stop =
        if has start "{" then
          embedded i (start + 1) (start + 1)
        else if
          Int.(start < length)
          && (Char.is_lowercase source.[start] || Char.equal source.[start] '_')
        then (
          let rec stop j =
            if Int.(j < length) && ocaml_name_char source.[j] then
              stop (j + 1)
            else
              j
          in
          let stop = stop (start + 1) in
          let expression = String.sub source ~pos:start ~len:(stop - start) in
          if valid_expression expression then
            Ok (expression, stop)
          else
            fail i "invalid OCaml parameter name")
        else
          fail i "expected $name, $?name, ${expression} or $?{expression}"
      in
      scan
        stop
        ({ kind = Parameter { expression; optional; start = i; stop }; offset = i } :: acc))
    else if word_start source.[i] then (
      let rec stop j =
        if Int.(j < length) && word_char source.[j] then
          stop (j + 1)
        else
          j
      in
      let stop = stop (i + 1) in
      let word = String.sub source ~pos:i ~len:(stop - i) |> String.lowercase in
      scan stop ({ kind = Word word; offset = i } :: acc))
    else if List.mem [ '<'; '>'; '!' ] source.[i] ~equal:Char.equal then (
      let stop =
        if has (i + 1) "=" || has i "<>" then
          i + 2
        else
          i + 1
      in
      let operator = String.sub source ~pos:i ~len:(stop - i) in
      if String.equal operator "!" then
        fail i "expected !="
      else
        scan stop ({ kind = Operator operator; offset = i } :: acc))
    else if has i "::" || has i "||" then
      scan
        (i + 2)
        ({ kind = Operator (String.sub source ~pos:i ~len:2); offset = i } :: acc)
    else if
      List.mem
        [ '*'; '.'; ','; '='; '('; ')'; ';'; '+'; '-'; '/'; '%'; '['; ']' ]
        source.[i]
        ~equal:Char.equal
    then
      scan (i + 1) ({ kind = Symbol source.[i]; offset = i } :: acc)
    else
      fail i "unsupported SQL token in the supported subset"
  in
  scan 0 []
;;

type type_name =
  { names : string list
  ; dimensions : int
  ; modifiers : int list
  ; interval_fields : string list
  }

type expression =
  { node : expression_node
  ; offset : int
  }

and expression_node =
  | Column of string list
  | Parameter_value of parameter
  | String_literal of string
  | Number_literal of string
  | Bool_literal of bool
  | Null_literal
  | Default
  | Unary of string * expression
  | Binary of string * expression * expression
  | Cast of expression * type_name
  | Case of expression option * (expression * expression) list * expression option
  | Call of call
  | Like_escape of expression * expression
  | Is_null of expression * bool
  | Between of expression * expression * expression * bool
  | In_list of expression * expression list * bool
  | In_query of expression * statement * bool
  | Quantified of string * expression * expression * bool
  | Scalar of statement
  | Exists of statement

and call =
  { name : string list
  ; args : expression list
  ; star : bool
  ; distinct : bool
  ; order : ordering list
  ; filter : expression option
  ; over : window option
  }

and window =
  { parent : string option
  ; partition : expression list
  ; ordering : ordering list
  ; frame : frame option
  ; direct : bool
  ; offset : int
  }

and frame =
  { mode : string
  ; first : frame_bound
  ; last : frame_bound
  ; exclusion : string option
  }

and frame_bound =
  | Unbounded of bool
  | Current_row
  | Bounded of expression * bool

and ordering = expression * bool * bool option

and projection =
  | Field of expression * string option
  | All of reference

and relation =
  { relation : relation_node
  ; alias : string option
  ; columns : string list
  ; offset : int
  }

and relation_node =
  | Table of reference
  | Derived of statement
  | Lateral of statement
  | Function of call * bool
  | Join of relation * relation * join_kind * join_condition

and join_kind =
  | Inner
  | Left
  | Right
  | Full
  | Cross

and join_condition =
  | On of expression
  | Using of reference list
  | Natural
  | No_condition

and select =
  { projection : projection list
  ; from : relation option
  ; conditions : expression option
  ; group : expression list
  ; having : expression option
  ; distinct : bool
  ; windows : (string * window) list
  }

and conflict =
  { target : reference list option
  ; action : conflict_action
  }

and conflict_action =
  | Do_nothing
  | Do_update of assignment list * expression option

and assignment = reference * expression

and body =
  | Select of select
  | Set of string * bool * statement * statement
  | Nested of statement
  | Insert of
      reference
      * string option
      * reference list
      * expression list list option
      * statement option
      * conflict option
      * projection list
  | Update of
      reference
      * string option
      * assignment list
      * relation option
      * expression option
      * projection list
  | Delete of
      reference * string option * relation option * expression option * projection list

and cte =
  { name : string
  ; columns : string list
  ; query : statement
  ; offset : int
  }

and statement =
  { ctes : cte list
  ; recursive : bool
  ; body : body
  ; order : ordering list
  ; limit : expression option
  ; pagination_offset : expression option
  ; offset : int
  }

type parser = { mutable tokens : token list }

exception Parse_error of error

let reject offset message = Stdlib.raise (Parse_error { offset; message })

let pos parser =
  match parser.tokens with
  | [] -> 0
  | token :: _ -> token.offset
;;

let peek parser =
  match parser.tokens with
  | [] -> End
  | token :: _ -> token.kind
;;

let advance parser =
  match parser.tokens with
  | [] -> ()
  | _ :: rest -> parser.tokens <- rest
;;

let word parser name =
  match peek parser with
  | Word actual -> String.equal actual name
  | _ -> false
;;

let take_word parser name =
  if word parser name then (
    advance parser;
    true)
  else
    false
;;

let take_symbol parser wanted =
  match peek parser with
  | Symbol actual when Char.equal actual wanted ->
    advance parser;
    true
  | _ -> false
;;

let expect_word parser name =
  if not (take_word parser name) then
    reject (pos parser) ("expected " ^ String.uppercase name)
;;

let expect_symbol parser wanted =
  if not (take_symbol parser wanted) then
    reject (pos parser) ("expected " ^ String.of_char wanted)
;;

let boundary =
  [ "from"
  ; "where"
  ; "group"
  ; "having"
  ; "order"
  ; "limit"
  ; "offset"
  ; "union"
  ; "intersect"
  ; "except"
  ; "join"
  ; "inner"
  ; "left"
  ; "right"
  ; "full"
  ; "cross"
  ; "outer"
  ; "natural"
  ; "on"
  ; "using"
  ; "returning"
  ; "set"
  ; "values"
  ; "select"
  ; "with"
  ; "as"
  ; "when"
  ; "then"
  ; "else"
  ; "end"
  ; "asc"
  ; "desc"
  ; "nulls"
  ; "and"
  ; "or"
  ; "not"
  ; "is"
  ; "in"
  ; "like"
  ; "ilike"
  ; "between"
  ; "escape"
  ; "filter"
  ; "do"
  ; "conflict"
  ; "materialized"
  ; "search"
  ; "cycle"
  ; "for"
  ; "fetch"
  ; "window"
  ; "over"
  ; "partition"
  ; "rows"
  ; "range"
  ; "groups"
  ; "exclude"
  ; "preceding"
  ; "following"
  ; "lateral"
  ]
;;

let identifier parser =
  match peek parser with
  | Quoted value ->
    advance parser;
    value
  | Word value when not (List.mem boundary value ~equal:String.equal) ->
    advance parser;
    value
  | _ -> reject (pos parser) "expected SQL identifier"
;;

let reference parser =
  let offset = pos parser in
  let first = identifier parser in
  let rec loop names =
    if take_symbol parser '.' then
      loop (identifier parser :: names)
    else
      List.rev names
  in
  { names = loop [ first ]; offset }
;;

let list parser f =
  let first = f parser in
  let rec loop acc =
    if take_symbol parser ',' then
      loop (f parser :: acc)
    else
      List.rev acc
  in
  loop [ first ]
;;

let names parser =
  if take_symbol parser '(' then (
    let result = list parser identifier in
    expect_symbol parser ')';
    result)
  else
    []
;;

let alias parser =
  let result =
    if take_word parser "as" then
      Some (identifier parser)
    else (
      match
        peek parser
      with
      | Quoted _ -> Some (identifier parser)
      | Word name when not (List.mem boundary name ~equal:String.equal) ->
        Some (identifier parser)
      | _ -> None)
  in
  let columns =
    if Option.is_some result then
      names parser
    else
      []
  in
  result, columns
;;

let empty offset body =
  { ctes = []
  ; recursive = false
  ; body
  ; order = []
  ; limit = None
  ; pagination_offset = None
  ; offset
  }
;;

let expression offset node = { node; offset }

let rec parse_statement parser : statement =
  let offset = pos parser in
  let recursive, ctes =
    if take_word parser "with" then (
      let recursive = take_word parser "recursive" in
      let ctes =
        list parser (fun parser ->
          let offset = pos parser in
          let name = identifier parser in
          let columns = names parser in
          expect_word parser "as";
          if take_word parser "not" then
            expect_word parser "materialized"
          else
            ignore (take_word parser "materialized" : bool);
          expect_symbol parser '(';
          let query = parse_statement parser in
          expect_symbol parser ')';
          { name; columns; query; offset })
      in
      recursive, ctes)
    else
      false, []
  in
  let query = parse_set parser 0 in
  let order =
    if take_word parser "order" then (
      expect_word parser "by";
      parse_order parser)
    else
      []
  in
  let rec pagination limit pagination_offset =
    if word parser "limit" || word parser "offset" then (
      let offset = pos parser in
      let is_limit = take_word parser "limit" in
      if not is_limit then
        expect_word parser "offset";
      if
        (is_limit && Option.is_some limit)
        || ((not is_limit) && Option.is_some pagination_offset)
      then
        reject offset "duplicate pagination clause";
      let value =
        if is_limit && take_word parser "all" then
          expression offset Null_literal
        else
          parse_expression parser 0
      in
      if is_limit then
        pagination (Some value) pagination_offset
      else
        pagination limit (Some value))
    else
      limit, pagination_offset
  in
  let limit, pagination_offset = pagination None None in
  { query with ctes; recursive; order; limit; pagination_offset; offset }

and parse_set parser minimum : statement =
  let left =
    if take_symbol parser '(' then (
      let offset = pos parser in
      let query = parse_statement parser in
      expect_symbol parser ')';
      (match query.body with
       | Insert _ | Update _ | Delete _ ->
         reject offset "data-modifying statements cannot be parenthesized query operands"
       | _ -> ());
      empty offset (Nested query))
    else
      parse_body parser
  in
  let rec loop (left : statement) =
    let op, precedence =
      match peek parser with
      | Word "union" -> "union", 1
      | Word "except" -> "except", 1
      | Word "intersect" -> "intersect", 2
      | _ -> "", 0
    in
    if Int.(precedence = 0 || precedence < minimum) then
      left
    else (
      advance parser;
      let all = take_word parser "all" in
      if not all then
        ignore (take_word parser "distinct" : bool);
      let right = parse_set parser (precedence + 1) in
      loop (empty left.offset (Set (op, all, left, right))))
  in
  loop left

and parse_body parser : statement =
  let offset = pos parser in
  if take_word parser "select" then (
    let distinct = take_word parser "distinct" in
    if not distinct then
      ignore (take_word parser "all" : bool);
    let projection = parse_projection parser in
    let from =
      if take_word parser "from" then
        Some (parse_from parser)
      else
        None
    in
    let conditions = parse_where parser in
    let group =
      if take_word parser "group" then (
        expect_word parser "by";
        list parser (fun p -> parse_expression p 0))
      else
        []
    in
    let having =
      if take_word parser "having" then
        Some (parse_expression parser 0)
      else
        None
    in
    let windows =
      if take_word parser "window" then
        list parser (fun parser ->
          let name = identifier parser in
          expect_word parser "as";
          (match peek parser with
           | Symbol '(' -> ()
           | _ -> reject (pos parser) "WINDOW definition requires parentheses");
          name, parse_window parser)
      else
        []
    in
    empty
      offset
      (Select { projection; from; conditions; group; having; distinct; windows }))
  else if take_word parser "insert" then (
    expect_word parser "into";
    let target = reference parser in
    let target_alias =
      if take_word parser "as" then
        Some (identifier parser)
      else
        None
    in
    let columns =
      if take_symbol parser '(' then (
        let cols = list parser reference in
        expect_symbol parser ')';
        cols)
      else
        []
    in
    let rows, query =
      if take_word parser "default" then (
        expect_word parser "values";
        None, None)
      else if take_word parser "values" then (
        let rows =
          list parser (fun p ->
            expect_symbol p '(';
            let row = list p (fun p -> parse_expression p 0) in
            expect_symbol p ')';
            row)
        in
        Some rows, None)
      else
        None, Some (parse_statement parser)
    in
    let conflict =
      if take_word parser "on" then (
        expect_word parser "conflict";
        let target =
          if take_symbol parser '(' then (
            let cols = list parser reference in
            expect_symbol parser ')';
            Some cols)
          else
            None
        in
        expect_word parser "do";
        let action =
          if take_word parser "nothing" then
            Do_nothing
          else (
            expect_word parser "update";
            expect_word parser "set";
            let assignments = parse_assignments parser in
            let condition = parse_where parser in
            Do_update (assignments, condition))
        in
        Some { target; action })
      else
        None
    in
    let result = parse_returning parser in
    empty offset (Insert (target, target_alias, columns, rows, query, conflict, result)))
  else if take_word parser "update" then (
    let target = reference parser in
    let target_alias, _ = alias parser in
    expect_word parser "set";
    let assignments = parse_assignments parser in
    let from =
      if take_word parser "from" then
        Some (parse_from parser)
      else
        None
    in
    let condition = parse_where parser in
    let result = parse_returning parser in
    empty offset (Update (target, target_alias, assignments, from, condition, result)))
  else if take_word parser "delete" then (
    expect_word parser "from";
    let target = reference parser in
    let target_alias, _ = alias parser in
    let using =
      if take_word parser "using" then
        Some (parse_from parser)
      else
        None
    in
    let condition = parse_where parser in
    let result = parse_returning parser in
    empty offset (Delete (target, target_alias, using, condition, result)))
  else
    reject offset "expected SELECT, INSERT, UPDATE or DELETE"

and parse_assignments parser =
  list parser (fun p ->
    let column = reference p in
    expect_symbol p '=';
    column, parse_expression p 0)

and parse_where parser =
  if take_word parser "where" then
    Some (parse_expression parser 0)
  else
    None

and parse_returning parser =
  if take_word parser "returning" then
    parse_projection parser
  else
    []

and parse_projection parser =
  list parser (fun parser ->
    let saved = parser.tokens in
    let offset = pos parser in
    let rec wildcard acc =
      match peek parser with
      | Symbol '*' ->
        advance parser;
        Some (All { names = List.rev acc; offset })
      | Word value | Quoted value ->
        advance parser;
        if take_symbol parser '.' then
          wildcard (value :: acc)
        else
          None
      | _ -> None
    in
    match wildcard [] with
    | Some result -> result
    | None ->
      parser.tokens <- saved;
      let value = parse_expression parser 0 in
      let name, columns = alias parser in
      if not (List.is_empty columns) then
        reject offset "projection alias cannot rename columns";
      Field (value, name))

and parse_from parser : relation =
  let first = parse_joins parser in
  let rec loop (left : relation) =
    if take_symbol parser ',' then (
      let right = parse_joins parser in
      loop
        { relation = Join (left, right, Cross, No_condition)
        ; alias = None
        ; columns = []
        ; offset = left.offset
        })
    else
      left
  in
  loop first

and parse_joins parser : relation =
  let first = parse_relation parser in
  let rec loop (left : relation) =
    let natural = take_word parser "natural" in
    let kind =
      if take_word parser "left" then
        Some Left
      else if take_word parser "right" then
        Some Right
      else if take_word parser "full" then
        Some Full
      else if take_word parser "cross" then
        Some Cross
      else if take_word parser "inner" then
        Some Inner
      else if word parser "join" || natural then
        Some Inner
      else
        None
    in
    match kind with
    | None -> left
    | Some kind ->
      let outer = take_word parser "outer" in
      if
        outer
        &&
        match kind with
        | Inner | Cross -> true
        | _ -> false
      then
        reject (pos parser) "OUTER requires LEFT, RIGHT or FULL";
      if
        natural
        &&
        match kind with
        | Cross -> true
        | _ -> false
      then
        reject (pos parser) "NATURAL CROSS JOIN is invalid";
      expect_word parser "join";
      let right = parse_relation parser in
      let condition =
        if natural then
          Natural
        else (
          match
            kind
          with
          | Cross -> No_condition
          | Inner | Left | Right | Full ->
            if take_word parser "on" then
              On (parse_expression parser 0)
            else if take_word parser "using" then (
              expect_symbol parser '(';
              let columns = list parser reference in
              expect_symbol parser ')';
              Using columns)
            else
              reject (pos parser) "expected ON or USING")
      in
      loop
        { relation = Join (left, right, kind, condition)
        ; alias = None
        ; columns = []
        ; offset = left.offset
        }
  in
  loop first

and parse_relation parser : relation =
  let offset = pos parser in
  let lateral = take_word parser "lateral" in
  let base =
    if take_symbol parser '(' then (
      let base =
        if word parser "select" || word parser "with" then
          { relation =
              (let query = parse_statement parser in
               if lateral then
                 Lateral query
               else
                 Derived query)
          ; alias = None
          ; columns = []
          ; offset
          }
        else
          parse_from parser
      in
      expect_symbol parser ')';
      base)
    else (
      let expression = parse_atom parser in
      let relation =
        match expression.node with
        | Column names -> Table { names; offset }
        | Call call ->
          let ordinality =
            if take_word parser "with" then (
              expect_word parser "ordinality";
              true)
            else
              false
          in
          Function (call, ordinality)
        | _ -> reject offset "expected table or supported table function"
      in
      { relation; alias = None; columns = []; offset })
  in
  if lateral then (
    match
      base.relation
    with
    | Lateral _ | Function _ -> ()
    | _ -> reject offset "LATERAL requires a derived SELECT");
  let new_alias, columns = alias parser in
  let alias =
    match new_alias with
    | None -> base.alias
    | Some name -> Some name
  in
  let columns =
    if Option.is_none new_alias then
      base.columns
    else
      columns
  in
  (match base.relation, alias with
   | (Derived _ | Lateral _), None -> reject offset "subquery in FROM requires an alias"
   | _ -> ());
  { base with alias; columns; offset }

and parse_order parser =
  list parser (fun parser ->
    let value = parse_expression parser 0 in
    let descending =
      if take_word parser "desc" then
        true
      else (
        ignore (take_word parser "asc" : bool);
        false)
    in
    let nulls =
      if take_word parser "nulls" then
        if take_word parser "first" then
          Some true
        else (
          expect_word parser "last";
          Some false)
      else
        None
    in
    value, descending, nulls)

and parse_expression parser minimum : expression =
  let offset = pos parser in
  let first =
    if take_word parser "not" then
      expression offset (Unary ("not", parse_expression parser 30))
    else if take_symbol parser '+' then
      expression offset (Unary ("+", parse_expression parser 80))
    else if take_symbol parser '-' then
      expression offset (Unary ("-", parse_expression parser 80))
    else
      parse_atom parser
  in
  let rec loop (left : expression) =
    match peek parser with
    | Operator "::" when Int.(minimum <= 90) ->
      advance parser;
      loop (expression left.offset (Cast (left, parse_type parser)))
    | _ ->
      let saved = parser.tokens in
      let negative =
        if Int.(minimum <= 40) then
          take_word parser "not"
        else
          false
      in
      if Int.(minimum <= 40) && take_word parser "is" then (
        let negative = take_word parser "not" in
        if take_word parser "distinct" then (
          expect_word parser "from";
          let right = parse_expression parser 41 in
          loop
            (expression
               left.offset
               (Binary
                  ( (if negative then
                       "is not distinct from"
                     else
                       "is distinct from")
                  , left
                  , right ))))
        else (
          expect_word parser "null";
          loop (expression left.offset (Is_null (left, negative)))))
      else if Int.(minimum <= 40) && take_word parser "between" then (
        let low = parse_expression parser 41 in
        expect_word parser "and";
        let high = parse_expression parser 41 in
        loop (expression left.offset (Between (left, low, high, negative))))
      else if Int.(minimum <= 40) && take_word parser "in" then (
        expect_symbol parser '(';
        let result =
          if word parser "select" || word parser "with" then
            In_query (left, parse_statement parser, negative)
          else
            In_list (left, list parser (fun p -> parse_expression p 0), negative)
        in
        expect_symbol parser ')';
        loop (expression left.offset result))
      else (
        let op, priority =
          match peek parser with
          | Word "or" -> "or", 10
          | Word "and" -> "and", 20
          | Word (("like" | "ilike") as op) -> op, 40
          | Symbol '=' -> "=", 40
          | Operator (("<" | ">" | "<=" | ">=" | "<>" | "!=") as op) -> op, 40
          | Operator (("||" | "->" | "->>" | "#>" | "#>>") as op) -> op, 50
          | Symbol (('+' | '-') as op) -> String.of_char op, 60
          | Symbol (('*' | '/' | '%') as op) -> String.of_char op, 70
          | _ -> "", 0
        in
        if Int.(priority = 0 || priority < minimum) then (
          parser.tokens <- saved;
          left)
        else (
          advance parser;
          let result =
            if
              (String.equal op "="
               || List.mem [ "<"; ">"; "<="; ">="; "<>"; "!=" ] op ~equal:String.equal)
              && (word parser "any" || word parser "all")
            then (
              let any = take_word parser "any" in
              if not any then
                expect_word parser "all";
              expect_symbol parser '(';
              let right =
                if word parser "select" || word parser "with" then
                  expression (pos parser) (Scalar (parse_statement parser))
                else
                  parse_expression parser 0
              in
              expect_symbol parser ')';
              Quantified (op, left, right, any))
            else
              Binary (op, left, parse_expression parser (priority + 1))
          in
          let result = expression left.offset result in
          let result =
            if negative then
              expression left.offset (Unary ("not", result))
            else
              result
          in
          let result =
            if
              (String.equal op "like" || String.equal op "ilike")
              && take_word parser "escape"
            then
              expression left.offset (Like_escape (result, parse_expression parser 41))
            else
              result
          in
          loop result))
  in
  loop first

and parse_atom parser : expression =
  let offset = pos parser in
  match peek parser with
  | Parameter value ->
    advance parser;
    expression offset (Parameter_value value)
  | String_sql value ->
    advance parser;
    expression offset (String_literal value)
  | Number value ->
    advance parser;
    expression offset (Number_literal value)
  | Word "null" ->
    advance parser;
    expression offset Null_literal
  | Word "default" ->
    advance parser;
    expression offset Default
  | Word (("true" | "false") as value) ->
    advance parser;
    expression offset (Bool_literal (String.equal value "true"))
  | Word "exists" ->
    advance parser;
    expect_symbol parser '(';
    let query = parse_statement parser in
    expect_symbol parser ')';
    expression offset (Exists query)
  | Word "case" ->
    advance parser;
    let value =
      if word parser "when" then
        None
      else
        Some (parse_expression parser 0)
    in
    let rec branches acc =
      if take_word parser "when" then (
        let condition = parse_expression parser 0 in
        expect_word parser "then";
        let result = parse_expression parser 0 in
        branches ((condition, result) :: acc))
      else
        List.rev acc
    in
    let branches = branches [] in
    if List.is_empty branches then
      reject offset "CASE requires WHEN";
    let otherwise =
      if take_word parser "else" then
        Some (parse_expression parser 0)
      else
        None
    in
    expect_word parser "end";
    expression offset (Case (value, branches, otherwise))
  | Word "cast" ->
    advance parser;
    expect_symbol parser '(';
    let value = parse_expression parser 0 in
    expect_word parser "as";
    let target = parse_type parser in
    expect_symbol parser ')';
    expression offset (Cast (value, target))
  | Symbol '(' ->
    advance parser;
    let value =
      if word parser "select" || word parser "with" then
        expression offset (Scalar (parse_statement parser))
      else
        parse_expression parser 0
    in
    expect_symbol parser ')';
    value
  | Word _ | Quoted _ ->
    let keyword =
      match peek parser with
      | Word _ -> true
      | _ -> false
    in
    let name = reference parser in
    if take_symbol parser '(' then (
      let function_name = List.last_exn name.names in
      let trim =
        keyword
        && String.equal function_name "trim"
        && Int.equal (List.length name.names) 1
      in
      let direction =
        if trim then
          if take_word parser "leading" then
            "ltrim"
          else if take_word parser "trailing" then
            "rtrim"
          else (
            ignore (take_word parser "both" : bool);
            "btrim")
        else
          function_name
      in
      let distinct = take_word parser "distinct" in
      if not distinct then
        ignore (take_word parser "all" : bool);
      let star = take_symbol parser '*' in
      let args =
        if
          star
          ||
          match peek parser with
          | Symbol ')' -> true
          | _ -> false
        then
          []
        else if trim && take_word parser "from" then
          [ parse_expression parser 0 ]
        else (
          let first = parse_expression parser 0 in
          if trim && take_word parser "from" then (
            let value = parse_expression parser 0 in
            [ value; first ])
          else if
            String.equal function_name "substring"
            && keyword
            && Int.equal (List.length name.names) 1
            && (word parser "from" || word parser "for")
          then (
            let start =
              if take_word parser "from" then
                parse_expression parser 0
              else
                expression offset (Number_literal "1")
            in
            if take_word parser "for" then
              [ first; start; parse_expression parser 0 ]
            else
              [ first; start ])
          else (
            let rec rest acc =
              if take_symbol parser ',' then
                rest (parse_expression parser 0 :: acc)
              else
                List.rev acc
            in
            rest [ first ]))
      in
      let order =
        if take_word parser "order" then (
          expect_word parser "by";
          parse_order parser)
        else
          []
      in
      expect_symbol parser ')';
      let filter =
        if take_word parser "filter" then (
          expect_symbol parser '(';
          expect_word parser "where";
          let value = parse_expression parser 0 in
          expect_symbol parser ')';
          Some value)
        else
          None
      in
      let over =
        if take_word parser "over" then
          Some (parse_window parser)
        else
          None
      in
      let names =
        if trim then
          [ direction ]
        else
          name.names
      in
      expression offset (Call { name = names; args; star; distinct; order; filter; over }))
    else
      expression offset (Column name.names)
  | _ -> reject offset "expected SQL expression"

and parse_window parser : window =
  let offset = pos parser in
  if not (take_symbol parser '(') then
    { parent = Some (identifier parser)
    ; partition = []
    ; ordering = []
    ; frame = None
    ; direct = true
    ; offset
    }
  else (
    let parent =
      match peek parser with
      | Word name
        when not
               (List.mem
                  [ "partition"; "order"; "rows"; "range"; "groups" ]
                  name
                  ~equal:String.equal) -> Some (identifier parser)
      | Quoted _ -> Some (identifier parser)
      | _ -> None
    in
    let partition =
      if take_word parser "partition" then (
        expect_word parser "by";
        list parser (fun p -> parse_expression p 0))
      else
        []
    in
    let ordering =
      if take_word parser "order" then (
        expect_word parser "by";
        parse_order parser)
      else
        []
    in
    let frame =
      match peek parser with
      | Word (("rows" | "range" | "groups") as mode) ->
        advance parser;
        let bound () =
          if take_word parser "unbounded" then (
            let preceding = take_word parser "preceding" in
            if not preceding then
              expect_word parser "following";
            Unbounded preceding)
          else if take_word parser "current" then (
            expect_word parser "row";
            Current_row)
          else (
            let value = parse_expression parser 0 in
            let preceding = take_word parser "preceding" in
            if not preceding then
              expect_word parser "following";
            Bounded (value, preceding))
        in
        let first, last =
          if take_word parser "between" then (
            let first = bound () in
            expect_word parser "and";
            first, bound ())
          else
            bound (), Current_row
        in
        let exclusion =
          if take_word parser "exclude" then
            if take_word parser "current" then (
              expect_word parser "row";
              Some "current row")
            else if take_word parser "group" then
              Some "group"
            else if take_word parser "ties" then
              Some "ties"
            else (
              expect_word parser "no";
              expect_word parser "others";
              Some "no others")
          else
            None
        in
        Some { mode; first; last; exclusion }
      | _ -> None
    in
    expect_symbol parser ')';
    { parent; partition; ordering; frame; direct = false; offset })

and parse_type parser =
  let quoted =
    match peek parser with
    | Quoted _ -> true
    | _ -> false
  in
  let name = reference parser in
  let names =
    match name.names, quoted with
    | [ "smallint" ], false -> [ "int2" ]
    | [ ("integer" | "int") ], false -> [ "int4" ]
    | [ "bigint" ], false -> [ "int8" ]
    | [ "real" ], false -> [ "float4" ]
    | [ "boolean" ], false -> [ "bool" ]
    | [ "decimal" ], false -> [ "numeric" ]
    | [ "char" ], false -> [ "bpchar" ]
    | [ "double" ], false ->
      expect_word parser "precision";
      [ "float8" ]
    | [ "character" ], false ->
      if take_word parser "varying" then
        [ "varchar" ]
      else
        [ "bpchar" ]
    | names, _ -> names
  in
  let modifiers () =
    if take_symbol parser '(' then (
      let values =
        list parser (fun parser ->
          let offset = pos parser in
          match peek parser with
          | Number value ->
            advance parser;
            (match Int.of_string_opt value with
             | Some value -> value
             | None -> reject offset "type modifier requires an integer")
          | _ -> reject offset "expected type modifier")
      in
      expect_symbol parser ')';
      values)
    else
      []
  in
  let values = modifiers () in
  let interval_fields =
    if List.equal String.equal names [ "interval" ] then (
      let field () =
        match peek parser with
        | Word (("year" | "month" | "day" | "hour" | "minute" | "second") as name) ->
          advance parser;
          Some name
        | _ -> None
      in
      match field () with
      | None -> []
      | Some first ->
        if take_word parser "to" then (
          match
            field ()
          with
          | Some last -> [ first; last ]
          | None -> reject (pos parser) "expected interval field")
        else
          [ first ])
    else
      []
  in
  let values =
    if List.is_empty interval_fields then
      values
    else (
      if not (List.is_empty values) then
        reject (pos parser) "interval precision follows SECOND";
      let precision = modifiers () in
      if
        (not (List.is_empty precision))
        && not (String.equal (List.last_exn interval_fields) "second")
      then
        reject (pos parser) "interval precision requires SECOND";
      precision)
  in
  let values =
    if
      List.is_empty values
      && (not quoted)
      && List.mem
           [ [ "char" ]; [ "character" ] ]
           name.names
           ~equal:(List.equal String.equal)
    then
      [ 1 ]
    else
      values
  in
  let names =
    match names with
    | [ "timestamp" ] | [ "time" ] ->
      if take_word parser "with" then (
        expect_word parser "time";
        expect_word parser "zone";
        if List.equal String.equal names [ "time" ] then
          [ "timetz" ]
        else
          [ "timestamptz" ])
      else if take_word parser "without" then (
        expect_word parser "time";
        expect_word parser "zone";
        names)
      else
        names
    | names -> names
  in
  let rec dimensions n =
    if take_symbol parser '[' then (
      expect_symbol parser ']';
      dimensions (n + 1))
    else
      n
  in
  { names; dimensions = dimensions 0; modifiers = values; interval_fields }
;;

let parse tokens =
  let parser = { tokens } in
  try
    let query = parse_statement parser in
    ignore (take_symbol parser ';' : bool);
    match peek parser with
    | End -> Ok query
    | _ -> fail (pos parser) "unsupported trailing SQL; expected end of statement"
  with
  | Parse_error error -> Error error
;;
