open! Base

type error =
  { offset : int
  ; message : string
  }

exception Invalid of error

let reject offset message = Stdlib.raise (Invalid { offset; message })
let alpha c = Char.is_alpha c || Char.equal c '_' || Int.(Char.to_int c >= 128)

let dollar_opener source start =
  let length = String.length source in
  let rec tag i =
    if Int.(i >= length) then
      None
    else if Char.equal source.[i] '$' then
      Some (String.sub source ~pos:start ~len:(i - start + 1), i + 1)
    else if alpha source.[i] || Char.is_digit source.[i] then
      tag (i + 1)
    else
      None
  in
  if Int.(start + 1 >= length) then
    None
  else if Char.equal source.[start + 1] '$' || alpha source.[start + 1] then
    tag (start + 1)
  else
    None
;;

let dollar source ~start ~delimiter ~body =
  match String.substr_index source ~pos:body ~pattern:delimiter with
  | None -> Error { offset = start; message = "unterminated dollar-quoted string" }
  | Some stop ->
    Ok (String.sub source ~pos:body ~len:(stop - body), stop + String.length delimiter)
;;

let quoted ~escape source ~quote =
  let length = String.length source in
  let buffer = Stdlib.Buffer.create 32 in
  let has i text =
    Int.(i + String.length text <= length)
    && String.equal (String.sub source ~pos:i ~len:(String.length text)) text
  in
  let hex = function
    | '0' .. '9' as c -> Char.to_int c - Char.to_int '0'
    | 'a' .. 'f' as c -> Char.to_int c - Char.to_int 'a' + 10
    | 'A' .. 'F' as c -> Char.to_int c - Char.to_int 'A' + 10
    | _ -> -1
  in
  let digits start count base =
    let rec loop i remaining value =
      if Int.(remaining = 0 || i >= length) then
        value, i
      else (
        let digit = hex source.[i] in
        if Int.(digit < 0 || digit >= base) then
          value, i
        else
          loop (i + 1) (remaining - 1) ((value * base) + digit))
    in
    loop start count 0
  in
  let byte offset value =
    let value = value land 255 in
    if Int.(value = 0) then
      reject offset "SQL string cannot contain NUL";
    Stdlib.Buffer.add_char buffer (Char.of_int_exn value)
  in
  let unicode start count =
    let value, stop = digits start count 16 in
    if not Int.(stop = start + count) then
      reject start "invalid Unicode escape";
    value, stop
  in
  let add_unicode offset value =
    if Int.(value = 0 || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) then
      reject offset "invalid Unicode code point";
    Stdlib.Buffer.add_utf_8_uchar buffer (Stdlib.Uchar.of_int value)
  in
  let rec trivia i newline =
    if Int.(i >= length) then
      i, newline
    else if Char.is_whitespace source.[i] then
      trivia (i + 1) (newline || Char.equal source.[i] '\n' || Char.equal source.[i] '\r')
    else if has i "--" then (
      let stop = Option.value (String.index_from source (i + 2) '\n') ~default:length in
      trivia stop newline)
    else
      i, newline
  in
  let rec loop i =
    if Int.(i >= length) then
      reject quote "unterminated SQL string literal"
    else if has i "''" then (
      Stdlib.Buffer.add_char buffer '\'';
      loop (i + 2))
    else if Char.equal source.[i] '\'' then (
      let next, newline = trivia (i + 1) false in
      if newline && Int.(next < length) && Char.equal source.[next] '\'' then
        loop (next + 1)
      else
        Stdlib.Buffer.contents buffer, i + 1)
    else if escape && Char.equal source.[i] '\\' then (
      if Int.(i + 1 >= length) then
        reject i "unterminated SQL escape";
      match source.[i + 1] with
      | 'b' ->
        byte i 8;
        loop (i + 2)
      | 'f' ->
        byte i 12;
        loop (i + 2)
      | 'n' ->
        byte i 10;
        loop (i + 2)
      | 'r' ->
        byte i 13;
        loop (i + 2)
      | 't' ->
        byte i 9;
        loop (i + 2)
      | '0' .. '7' ->
        let value, stop = digits (i + 1) 3 8 in
        byte i value;
        loop stop
      | 'x' ->
        let value, stop = digits (i + 2) 2 16 in
        if Int.(stop = i + 2) then (
          byte i (Char.to_int 'x');
          loop stop)
        else (
          byte i value;
          loop stop)
      | ('u' | 'U') as kind ->
        let value, stop =
          unicode
            (i + 2)
            (if Char.equal kind 'u' then
               4
             else
               8)
        in
        if Int.(value >= 0xd800 && value <= 0xdbff) then (
          if not (has stop "\\u" || has stop "\\U") then
            reject i "missing Unicode low surrogate";
          let count =
            if has stop "\\u" then
              4
            else
              8
          in
          let low, stop = unicode (stop + 2) count in
          if not Int.(low >= 0xdc00 && low <= 0xdfff) then
            reject i "invalid Unicode low surrogate";
          add_unicode i (0x10000 + ((value - 0xd800) * 1024) + low - 0xdc00);
          loop stop)
        else (
          add_unicode i value;
          loop stop)
      | c ->
        byte i (Char.to_int c);
        loop (i + 2))
    else (
      byte i (Char.to_int source.[i]);
      loop (i + 1))
  in
  try Ok (loop (quote + 1)) with
  | Invalid error -> Error error
;;
