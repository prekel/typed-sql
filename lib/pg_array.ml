open! Base

type 'a t =
  { dimensions : int list
  ; lower_bounds : int list
  ; elements : 'a option list
  }

let dimensions value = value.dimensions
let lower_bounds value = value.lower_bounds
let elements value = value.elements

let create ~dimensions ~lower_bounds ~elements =
  if
    (not (Int.equal (List.length dimensions) (List.length lower_bounds)))
    || List.exists dimensions ~f:(fun size -> Int.(size < 0))
  then
    Error "invalid array dimensions"
  else (
    let count =
      List.fold dimensions ~init:(Some 1) ~f:(fun count size ->
        Option.bind count ~f:(fun count ->
          if Int.(size = 0 || count <= max_value / size) then
            Some (count * size)
          else
            None))
    in
    match count with
    | None -> Error "array dimensions overflow"
    | Some count ->
      if
        Int.equal count (List.length elements)
        || (List.is_empty dimensions && List.is_empty elements)
      then
        Ok { dimensions; lower_bounds; elements }
      else
        Error "array dimensions do not match element count")
;;

type tree =
  | Scalar of string option
  | Nested of tree list

let of_string ~decode source =
  let length = String.length source in
  let index = ref 0 in
  let peek () =
    if Int.(!index < length) then
      Some source.[!index]
    else
      None
  in
  let skip_spaces () =
    while Option.value_map (peek ()) ~default:false ~f:Char.is_whitespace do
      Int.incr index
    done
  in
  let take character =
    skip_spaces ();
    match peek () with
    | Some found when Char.equal found character ->
      Int.incr index;
      Ok ()
    | _ -> Error "invalid PostgreSQL array syntax"
  in
  let parse_int () =
    skip_spaces ();
    let start = !index in
    (match peek () with
     | Some ('-' | '+') -> Int.incr index
     | _ -> ());
    while Option.value_map (peek ()) ~default:false ~f:Char.is_digit do
      Int.incr index
    done;
    let value = String.sub source ~pos:start ~len:(!index - start) in
    let value =
      if String.is_prefix value ~prefix:"+" then
        String.drop_prefix value 1
      else
        value
    in
    Int.of_string_opt value
  in
  let required option message =
    match option with
    | Some value -> Ok value
    | None -> Error message
  in
  let rec bounds acc =
    skip_spaces ();
    match peek () with
    | Some '[' ->
      Int.incr index;
      let open Result.Let_syntax in
      let%bind lower = required (parse_int ()) "invalid array lower bound" in
      let%bind () = take ':' in
      let%bind upper = required (parse_int ()) "invalid array upper bound" in
      let%bind () = take ']' in
      bounds ((lower, upper) :: acc)
    | _ -> Ok (List.rev acc)
  in
  let quoted () =
    let buffer = Buffer.create 32 in
    let rec loop () =
      match peek () with
      | None -> Error "unterminated array string"
      | Some '"' ->
        Int.incr index;
        Ok (Buffer.contents buffer)
      | Some '\\' ->
        Int.incr index;
        (match peek () with
         | None -> Error "unterminated array escape"
         | Some character ->
           Buffer.add_char buffer character;
           Int.incr index;
           loop ())
      | Some character ->
        Buffer.add_char buffer character;
        Int.incr index;
        loop ()
    in
    loop ()
  in
  let scalar () =
    skip_spaces ();
    match peek () with
    | Some '"' ->
      Int.incr index;
      Result.map (quoted ()) ~f:(fun value -> Scalar (Some value))
    | _ ->
      let start = !index in
      while
        Option.value_map (peek ()) ~default:false ~f:(fun character ->
          not (Char.equal character ',' || Char.equal character '}'))
      do
        Int.incr index
      done;
      let value = String.sub source ~pos:start ~len:(!index - start) |> String.strip in
      if String.is_empty value then
        Error "empty unquoted array element"
      else if String.Caseless.equal value "NULL" then
        Ok (Scalar None)
      else
        Ok (Scalar (Some value))
  in
  let rec nested () =
    let open Result.Let_syntax in
    let%bind () = take '{' in
    skip_spaces ();
    match peek () with
    | Some '}' ->
      Int.incr index;
      Ok (Nested [])
    | _ ->
      let rec items acc =
        skip_spaces ();
        let%bind item =
          match peek () with
          | Some '{' -> nested ()
          | _ -> scalar ()
        in
        skip_spaces ();
        match peek () with
        | Some ',' ->
          Int.incr index;
          items (item :: acc)
        | Some '}' ->
          Int.incr index;
          Ok (Nested (List.rev (item :: acc)))
        | _ -> Error "invalid array separator"
      in
      items []
  in
  let rec flatten = function
    | Scalar value -> Ok ([], [ value ])
    | Nested [] -> Ok ([ 0 ], [])
    | Nested children ->
      let open Result.Let_syntax in
      let%bind shapes = Result.all (List.map children ~f:flatten) in
      let first_dimensions = fst (List.hd_exn shapes) in
      if
        List.for_all shapes ~f:(fun (shape, _) ->
          List.equal Int.equal shape first_dimensions)
      then
        Ok (List.length children :: first_dimensions, List.concat_map shapes ~f:snd)
      else
        Error "ragged PostgreSQL array"
  in
  let open Result.Let_syntax in
  let%bind declared_bounds = bounds [] in
  let%bind () =
    if List.is_empty declared_bounds then
      Ok ()
    else
      take '='
  in
  let%bind tree = nested () in
  skip_spaces ();
  let%bind () =
    if Int.(!index = length) then
      Ok ()
    else
      Error "trailing PostgreSQL array input"
  in
  let%bind dimensions, raw = flatten tree in
  let lower_bounds =
    if List.is_empty declared_bounds then
      List.map dimensions ~f:(fun _ -> 1)
    else
      List.map declared_bounds ~f:fst
  in
  let expected = List.map declared_bounds ~f:(fun (lower, upper) -> upper - lower + 1) in
  let%bind () =
    if List.is_empty declared_bounds || List.equal Int.equal expected dimensions then
      Ok ()
    else
      Error "array bounds do not match elements"
  in
  let%bind elements =
    Result.all
      (List.map raw ~f:(function
         | None -> Ok None
         | Some text -> Result.map (decode text) ~f:Option.some))
  in
  create ~dimensions ~lower_bounds ~elements
;;

let to_string ~encode value =
  let open Result.Let_syntax in
  let%bind encoded =
    Result.all
      (List.map value.elements ~f:(function
         | None -> Ok "NULL"
         | Some element ->
           Result.map (encode element) ~f:(fun text ->
             let escaped =
               String.concat_map text ~f:(function
                 | '"' -> "\\\""
                 | '\\' -> "\\\\"
                 | character -> String.of_char character)
             in
             "\"" ^ escaped ^ "\"")))
  in
  let rec render dimensions values =
    match dimensions with
    | [] -> "{}", values
    | [ size ] ->
      let contents = List.take values size in
      "{" ^ String.concat ~sep:"," contents ^ "}", List.drop values size
    | size :: rest ->
      let rec children count values acc =
        if Int.(count = 0) then
          List.rev acc, values
        else (
          let child, values = render rest values in
          children (count - 1) values (child :: acc))
      in
      let children, values = children size values [] in
      "{" ^ String.concat ~sep:"," children ^ "}", values
  in
  let body, _ = render value.dimensions encoded in
  let bounds =
    List.map2_exn value.dimensions value.lower_bounds ~f:(fun size lower ->
      Stdlib.Printf.sprintf "[%d:%d]" lower (lower + size - 1))
    |> String.concat
  in
  Ok
    (if List.for_all value.lower_bounds ~f:(Int.equal 1) then
       body
     else
       bounds ^ "=" ^ body)
;;
