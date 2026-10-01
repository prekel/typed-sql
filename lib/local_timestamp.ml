open! Base

type t =
  { date : Date.t
  ; hour : int
  ; minute : int
  ; second : int
  ; microsecond : int
  }

let create ~date ~hour ~minute ~second ~microsecond =
  if
    Int.(hour < 0 || hour > 23)
    || Int.(minute < 0 || minute > 59)
    || Int.(second < 0 || second > 59)
    || Int.(microsecond < 0 || microsecond > 999_999)
  then
    Error "invalid local timestamp time"
  else
    Ok { date; hour; minute; second; microsecond }
;;

let date value = value.date
let hour value = value.hour
let minute value = value.minute
let second value = value.second
let microsecond value = value.microsecond

let of_string source =
  let source = String.strip source in
  if Int.(String.length source < 19) then
    Error "invalid local timestamp"
  else (
    let parse_int pos len = String.sub source ~pos ~len |> Int.of_string_opt in
    let date = Date.of_string (String.sub source ~pos:0 ~len:10) in
    let hour = parse_int 11 2 in
    let minute = parse_int 14 2 in
    let second = parse_int 17 2 in
    let fraction =
      if Int.(String.length source = 19) then
        Some 0
      else if Char.equal source.[19] '.' then (
        let digits = String.drop_prefix source 20 in
        if
          Int.(String.length digits > 0 && String.length digits <= 6)
          && String.for_all digits ~f:Char.is_digit
        then
          Int.of_string_opt (digits ^ String.make (6 - String.length digits) '0')
        else
          None)
      else
        None
    in
    match date, hour, minute, second, fraction with
    | Some date, Some hour, Some minute, Some second, Some microsecond
      when Char.equal source.[10] ' '
           && Char.equal source.[13] ':'
           && Char.equal source.[16] ':' ->
      create ~date ~hour ~minute ~second ~microsecond
    | _ -> Error "invalid local timestamp")
;;

let to_string value =
  let year, month, day = Date.to_ymd value.date in
  let base =
    Stdlib.Printf.sprintf
      "%04d-%02d-%02d %02d:%02d:%02d"
      year
      month
      day
      value.hour
      value.minute
      value.second
  in
  if Int.(value.microsecond = 0) then
    base
  else
    base ^ Stdlib.Printf.sprintf ".%06d" value.microsecond
;;
