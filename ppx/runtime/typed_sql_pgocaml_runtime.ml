open! Base

let string_of_array encode values =
  let quote value =
    let value = encode value in
    let escaped =
      String.concat_map value ~f:(function
        | '"' -> "\\\""
        | '\\' -> "\\\\"
        | character -> String.of_char character)
    in
    "\"" ^ escaped ^ "\""
  in
  "{"
  ^ String.concat
      ~sep:","
      (List.map values ~f:(function
         | None -> "NULL"
         | Some value -> quote value))
  ^ "}"
;;

let array_of_string source =
  let source = String.strip source in
  let length = String.length source in
  let failure =
    Error
      "invalid one-dimensional PostgreSQL array (nested arrays and explicit bounds are unsupported)"
  in
  if
    Int.(length < 2)
    || (not (Char.equal source.[0] '{'))
    || not (Char.equal source.[length - 1] '}')
  then
    failure
  else if Int.(length = 2) then
    Ok []
  else (
    let end_pos = length - 1 in
    let skip position =
      let rec loop position =
        if Int.(position < end_pos) && Char.is_whitespace source.[position] then
          loop (position + 1)
        else
          position
      in
      loop position
    in
    let rec quoted position acc =
      if Int.(position >= end_pos) then
        failure
      else (
        match
          source.[position]
        with
        | '"' -> Ok (Some (String.of_char_list (List.rev acc)), position + 1)
        | '\\' when Int.(position + 1 < end_pos) ->
          quoted (position + 2) (source.[position + 1] :: acc)
        | '\\' -> failure
        | character -> quoted (position + 1) (character :: acc))
    in
    let rec unquoted position acc =
      if Int.(position = end_pos) || Char.equal source.[position] ',' then (
        let value = String.strip (String.of_char_list (List.rev acc)) in
        if String.is_empty value then
          failure
        else
          Ok
            ( (if String.equal value "NULL" then
                 None
               else
                 Some value)
            , position ))
      else (
        match
          source.[position]
        with
        | '{' | '}' | '"' -> failure
        | '\\' when Int.(position + 1 < end_pos) ->
          unquoted (position + 2) (source.[position + 1] :: acc)
        | '\\' -> failure
        | character -> unquoted (position + 1) (character :: acc))
    in
    let rec elements position acc =
      let open Result.Let_syntax in
      let position = skip position in
      if Int.(position >= end_pos) then
        failure
      else (
        let%bind value, position =
          if Char.equal source.[position] '"' then
            quoted (position + 1) []
          else
            unquoted position []
        in
        let position = skip position in
        if Int.(position = end_pos) then
          Ok (List.rev (value :: acc))
        else if Char.equal source.[position] ',' then
          elements (position + 1) (value :: acc)
        else
          failure)
    in
    elements 1 [])
;;
