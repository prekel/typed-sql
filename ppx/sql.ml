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
  | Do_update of assignment list * (reference * parameter) list

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

type t =
  { source : string
  ; schema : string
  ; table : string
  ; alias : string option
  ; statement : statement
  ; projection : projection list
  ; conditions : (reference * parameter) list
  ; order : reference list
  }

type kind =
  | Word of string
  | Quoted of string
  | Symbol of char
  | Parameter of parameter
  | End

type token =
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
  ; "overriding"
  ]
;;

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
    else if Char.equal source.[i] '"' then (
      let%bind name, stop = quoted i (i + 1) [] in
      scan stop ({ kind = Quoted name; offset = i } :: acc))
    else if Char.equal source.[i] '$' then (
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
    else if List.mem [ '*'; '.'; ','; '='; '('; ')'; ';' ] source.[i] ~equal:Char.equal
    then
      scan (i + 1) ({ kind = Symbol source.[i]; offset = i } :: acc)
    else
      fail i "unsupported SQL token in the supported subset"
  in
  scan 0 []
;;

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

let rec condition tokens =
  let open Result.Let_syntax in
  match symbol '(' tokens with
  | Some rest ->
    let%bind conditions, rest = conjunction rest in
    let%map rest = expect_symbol ')' rest in
    conditions, rest
  | None ->
    let%bind column, _, rest = reference ~star:false tokens in
    let%bind rest = expect_symbol '=' rest in
    (match rest with
     | { kind = Parameter parameter; _ } :: rest -> Ok ([ column, parameter ], rest)
     | _ -> fail (position rest) "expected an OCaml bind parameter after =")

and conjunction tokens =
  let open Result.Let_syntax in
  let%bind left, rest = condition tokens in
  match keyword "and" rest with
  | None -> Ok (left, rest)
  | Some rest ->
    let%map right, rest = conjunction rest in
    left @ right, rest
;;

let where tokens =
  match keyword "where" tokens with
  | None -> Ok ([], tokens)
  | Some rest -> conjunction rest
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

let parse source =
  let open Result.Let_syntax in
  let%bind tokens = lex source in
  let%bind (schema, table, alias), statement, projection, conditions, order, tokens =
    match tokens with
    | { kind = Word name; _ } :: rest when String.equal name "select" ->
      let%bind fields, rest = projection rest in
      let%bind rest = expect_keyword "from" rest in
      let%bind table, rest = table_source ~bare_alias:true rest in
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
      table, Select, fields, conditions, order, rest
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
      table, Insert { columns; rows; conflict }, fields, [], [], rest
    | { kind = Word name; _ } :: rest when String.equal name "update" ->
      let%bind table, rest = table_source ~bare_alias:true rest in
      let%bind rest = expect_keyword "set" rest in
      let%bind values, rest = assignments ~excluded:false rest in
      let%bind conditions, rest = where rest in
      let%map fields, rest = returning rest in
      table, Update values, fields, conditions, [], rest
    | { kind = Word name; _ } :: rest when String.equal name "delete" ->
      let%bind rest = expect_keyword "from" rest in
      let%bind table, rest = table_source ~bare_alias:true rest in
      let%bind conditions, rest = where rest in
      let%map fields, rest = returning rest in
      table, Delete, fields, conditions, [], rest
    | _ -> fail (position tokens) "expected SELECT, INSERT, UPDATE or DELETE"
  in
  let tokens = Option.value (symbol ';' tokens) ~default:tokens in
  match tokens with
  | [ { kind = End; _ } ] ->
    Ok { source; schema; table; alias; statement; projection; conditions; order }
  | token :: _ -> fail token.offset "unsupported trailing SQL; expected end of statement"
  | [] -> fail (String.length source) "SQL parser lost its end-of-input marker"
;;
