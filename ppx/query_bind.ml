open! Base

type t =
  { sql : string
  ; parameters : Sql.parameter list
  }

let scan source =
  let length = String.length source in
  let has i text =
    Int.(i + String.length text <= length)
    && String.equal (String.sub source ~pos:i ~len:(String.length text)) text
  in
  let fail offset message = Error { Sql.offset; message } in
  let name_start c = Char.is_lowercase c || Char.equal c '_' in
  let name_char c = Char.is_alphanum c || Char.equal c '_' || Char.equal c '\'' in
  let sql_word c =
    Char.is_alphanum c
    || Char.equal c '_'
    || Char.equal c '$'
    || Int.(Char.to_int c >= 128)
  in
  let valid_expression expression =
    Result.is_ok
      (Result.try_with (fun () ->
         Ppxlib.Parse.expression (Stdlib.Lexing.from_string expression)))
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
  let rec continuation i newline =
    if Int.(i >= length) then
      i, newline
    else if Char.is_whitespace source.[i] then
      continuation
        (i + 1)
        (newline || Char.equal source.[i] '\n' || Char.equal source.[i] '\r')
    else if has i "--" then
      continuation
        (Option.value (String.index_from source (i + 2) '\n') ~default:length)
        newline
    else
      i, newline
  in
  let rec quoted start quote escape i =
    if Int.(i >= length) then
      fail start "unterminated SQL quoted token"
    else if escape && Char.equal source.[i] '\\' then
      quoted start quote escape (i + 2)
    else if Char.equal source.[i] quote then
      if Int.(i + 1 < length) && Char.equal source.[i + 1] quote then
        quoted start quote escape (i + 2)
      else (
        let next, newline = continuation (i + 1) false in
        if
          Char.equal quote '\''
          && newline
          && Int.(next < length)
          && Char.equal source.[next] '\''
        then
          quoted start quote escape (next + 1)
        else
          Ok (i + 1))
    else
      quoted start quote escape (i + 1)
  in
  let rec embedded start first i =
    if Int.(i >= length) then
      fail start "unterminated or invalid OCaml parameter expression"
    else if Char.equal source.[i] '}' then (
      let expression = String.sub source ~pos:first ~len:(i - first) in
      if valid_expression expression then
        Ok (expression, i + 1)
      else
        embedded start first (i + 1))
    else
      embedded start first (i + 1)
  in
  let buffer = Stdlib.Buffer.create length in
  let copy first stop = Stdlib.Buffer.add_substring buffer source first (stop - first) in
  let rec scan i first count parameters =
    let open Result.Let_syntax in
    if Int.(i >= length) then (
      copy first length;
      Ok { sql = Stdlib.Buffer.contents buffer; parameters = List.rev parameters })
    else if has i "--" then (
      let stop = Option.value (String.index_from source (i + 2) '\n') ~default:length in
      scan stop first count parameters)
    else if has i "/*" then (
      let%bind stop = comment i 1 (i + 2) in
      scan stop first count parameters)
    else if Char.equal source.[i] '\'' || Char.equal source.[i] '"' then (
      let escape =
        Char.equal source.[i] '\''
        && Int.(i > 0)
        && (Char.equal source.[i - 1] 'E' || Char.equal source.[i - 1] 'e')
        && (Int.(i = 1) || not (sql_word source.[i - 2]))
      in
      let%bind stop = quoted i source.[i] escape (i + 1) in
      scan stop first count parameters)
    else if Char.equal source.[i] '$' then (
      match
        Sql_string.dollar_opener source i
      with
      | Some (delimiter, body) ->
        let%bind stop =
          match String.substr_index source ~pos:body ~pattern:delimiter with
          | Some stop -> Ok (stop + String.length delimiter)
          | None -> fail i "unterminated dollar-quoted string"
        in
        scan stop first count parameters
      | None ->
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
          else if Int.(start < length) && name_start source.[start] then (
            let rec finish j =
              if Int.(j < length) && name_char source.[j] then
                finish (j + 1)
              else
                j
            in
            let stop = finish (start + 1) in
            let expression = String.sub source ~pos:start ~len:(stop - start) in
            if valid_expression expression then
              Ok (expression, stop)
            else
              fail i "invalid OCaml parameter name")
          else
            fail i "expected $name, $?name, ${expression} or $?{expression}"
        in
        copy first i;
        Stdlib.Buffer.add_string buffer ("$" ^ Int.to_string (count + 1));
        scan
          stop
          stop
          (count + 1)
          ({ Sql.expression; optional; start = i; stop } :: parameters))
    else if
      Char.is_alpha source.[i]
      || Char.equal source.[i] '_'
      || Int.(Char.to_int source.[i] >= 128)
    then (
      let rec finish j =
        if Int.(j < length) && sql_word source.[j] then
          finish (j + 1)
        else
          j
      in
      scan (finish (i + 1)) first count parameters)
    else
      scan (i + 1) first count parameters
  in
  scan 0 0 0 []
;;
