open! Base

type operation =
  | Select
  | Insert
  | Update
  | Delete
  | Unsupported

type t =
  { operation : operation
  ; top_level_only : bool
  ; terminator : int option
  }

type token =
  | Word of string
  | Name
  | Open
  | Close
  | Comma
  | Semi
  | Other

type located =
  { token : token
  ; offset : int
  }

let tokens source =
  let length = String.length source in
  let has i text =
    Int.(i + String.length text <= length)
    && String.equal (String.sub source ~pos:i ~len:(String.length text)) text
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
  let rec quote delimiter escape i =
    if Int.(i >= length) then
      length
    else if escape && Char.equal source.[i] '\\' then
      quote delimiter escape (i + 2)
    else if Char.equal source.[i] delimiter then
      if Int.(i + 1 < length) && Char.equal source.[i + 1] delimiter then
        quote delimiter escape (i + 2)
      else (
        let next, newline = continuation (i + 1) false in
        if
          Char.equal delimiter '\''
          && newline
          && Int.(next < length)
          && Char.equal source.[next] '\''
        then
          quote delimiter escape (next + 1)
        else
          i + 1)
    else
      quote delimiter escape (i + 1)
  in
  let rec comment depth i =
    if Int.(i >= length) then
      length
    else if has i "/*" then
      comment (depth + 1) (i + 2)
    else if has i "*/" then
      if Int.equal depth 1 then
        i + 2
      else
        comment (depth - 1) (i + 2)
    else
      comment depth (i + 1)
  in
  let word c =
    Char.is_alphanum c
    || Char.equal c '_'
    || Char.equal c '$'
    || Int.(Char.to_int c >= 128)
  in
  let rec scan i acc =
    if Int.(i >= length) then
      List.rev acc
    else if Char.is_whitespace source.[i] then
      scan (i + 1) acc
    else if has i "--" then
      scan (Option.value (String.index_from source (i + 2) '\n') ~default:length) acc
    else if has i "/*" then
      scan (comment 1 (i + 2)) acc
    else if Char.equal source.[i] '"' then
      scan (quote '"' false (i + 1)) ({ token = Name; offset = i } :: acc)
    else if Char.equal source.[i] '\'' then
      scan (quote '\'' false (i + 1)) ({ token = Other; offset = i } :: acc)
    else if has i "E'" || has i "e'" then
      scan (quote '\'' true (i + 2)) ({ token = Other; offset = i } :: acc)
    else if
      Char.equal source.[i] '$' && Option.is_some (Query_bind.dollar_opener source i)
    then (
      let delimiter, body = Option.value_exn (Query_bind.dollar_opener source i) in
      let stop =
        Option.value_map
          (String.substr_index source ~pos:body ~pattern:delimiter)
          ~default:length
          ~f:(fun stop -> stop + String.length delimiter)
      in
      scan stop ({ token = Other; offset = i } :: acc))
    else if
      Char.is_alpha source.[i]
      || Char.equal source.[i] '_'
      || Int.(Char.to_int source.[i] >= 128)
    then (
      let rec finish j =
        if Int.(j < length) && word source.[j] then
          finish (j + 1)
        else
          j
      in
      let stop = finish (i + 1) in
      scan
        stop
        ({ token = Word (String.lowercase (String.sub source ~pos:i ~len:(stop - i)))
         ; offset = i
         }
         :: acc))
    else (
      let token =
        match source.[i] with
        | '(' -> Open
        | ')' -> Close
        | ',' -> Comma
        | ';' -> Semi
        | _ -> Other
      in
      scan (i + 1) ({ token; offset = i } :: acc))
  in
  scan 0 []
;;

let analyze sql =
  let tokens = tokens sql in
  let tokens, terminator =
    match List.rev tokens with
    | { token = Semi; offset } :: rest -> List.rev rest, Some offset
    | _ -> tokens, None
  in
  let unsupported = Unsupported, true, false in
  let rec group depth acc = function
    | [] -> None
    | { token = Close; _ } :: rest when Int.equal depth 1 -> Some (List.rev acc, rest)
    | ({ token = Open; _ } as tok) :: rest -> group (depth + 1) (tok :: acc) rest
    | ({ token = Close; _ } as tok) :: rest -> group (depth - 1) (tok :: acc) rest
    | tok :: rest -> group depth (tok :: acc) rest
  in
  let rec classify = function
    | { token = Word "with"; _ } :: rest ->
      let rest =
        match rest with
        | { token = Word "recursive"; _ } :: rest -> rest
        | _ -> rest
      in
      ctes false rest
    | { token = Word ("select" | "values" | "table"); _ } :: rest ->
      if
        List.exists rest ~f:(fun t ->
          match t.token with
          | Semi -> true
          | _ -> false)
      then
        unsupported
      else
        Select, locking 0 rest, false
    | { token = Word "insert"; _ } :: _ -> Insert, true, true
    | { token = Word "update"; _ } :: _ -> Update, true, true
    | { token = Word "delete"; _ } :: _ -> Delete, true, true
    | _ -> unsupported
  and locking depth = function
    | { token = Open; _ } :: rest -> locking (depth + 1) rest
    | { token = Close; _ } :: rest -> locking (depth - 1) rest
    | { token = Word "for"; _ }
      :: { token = Word ("update" | "no" | "share" | "key"); _ }
      :: _
      when Int.equal depth 0 -> true
    | _ :: rest -> locking depth rest
    | [] -> false
  and ctes modified = function
    | { token = Word _ | Name; _ } :: rest ->
      let rest =
        match rest with
        | { token = Open; _ } :: rest -> Option.map (group 1 [] rest) ~f:snd
        | _ -> Some rest
      in
      (match rest with
       | Some ({ token = Word "as"; _ } :: rest) ->
         let rest =
           match rest with
           | { token = Word "not"; _ } :: { token = Word "materialized"; _ } :: rest ->
             rest
           | { token = Word "materialized"; _ } :: rest -> rest
           | _ -> rest
         in
         (match rest with
          | { token = Open; _ } :: body ->
            (match group 1 [] body with
             | None -> unsupported
             | Some (body, rest) ->
               let operation, _, modifies = classify body in
               if
                 match operation with
                 | Unsupported -> true
                 | _ -> false
               then
                 unsupported
               else (
                 let modified = modified || modifies in
                 match rest with
                 | { token = Comma; _ } :: rest -> ctes modified rest
                 | _ ->
                   let operation, restricted, modifies = classify rest in
                   operation, modified || restricted, modified || modifies))
          | _ -> unsupported)
       | _ -> unsupported)
    | _ -> unsupported
  in
  let operation, top_level_only, _ =
    if
      List.exists tokens ~f:(fun located ->
        match located.token with
        | Semi -> true
        | _ -> false)
    then
      unsupported
    else
      classify tokens
  in
  { operation; top_level_only; terminator }
;;
