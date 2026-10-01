open! Base

type t =
  { months : int
  ; days : int
  ; microseconds : int64
  }

let create ~months ~days ~microseconds = { months; days; microseconds }
let months value = value.months
let days value = value.days
let microseconds value = value.microseconds

let time_to_microseconds value =
  let direction, value =
    if String.is_prefix value ~prefix:"-" then
      -1L, String.drop_prefix value 1
    else if String.is_prefix value ~prefix:"+" then
      1L, String.drop_prefix value 1
    else
      1L, value
  in
  match String.split value ~on:':' with
  | [ hours; minutes; seconds ] ->
    let seconds, fraction =
      match String.lsplit2 seconds ~on:'.' with
      | Some pair -> pair
      | None -> seconds, ""
    in
    let parse = Int64.of_string_opt in
    (match parse hours, parse minutes, parse seconds with
     | Some hours, Some minutes, Some seconds
       when Int64.(minutes >= 0L && minutes < 60L && seconds >= 0L && seconds < 60L)
            && Int.(String.length fraction <= 6)
            && String.for_all fraction ~f:Char.is_digit ->
       let fraction = fraction ^ String.make (6 - String.length fraction) '0' in
       Option.map (parse fraction) ~f:(fun micros ->
         Int64.(
           direction
           * ((((((hours * 60L) + minutes) * 60L) + seconds) * 1_000_000L) + micros)))
     | _ -> None)
  | _ -> None
;;

let of_string source =
  let tokens =
    String.split (String.strip source) ~on:' '
    |> List.filter ~f:(fun token -> not (String.is_empty token))
  in
  let rec loop months days microseconds = function
    | [] -> Ok { months; days; microseconds }
    | [ "ago" ] ->
      Ok { months = -months; days = -days; microseconds = Int64.neg microseconds }
    | time :: rest when String.mem time ':' ->
      (match time_to_microseconds time with
       | Some time -> loop months days Int64.(microseconds + time) rest
       | None -> Error "invalid interval time")
    | quantity :: unit_ :: rest ->
      (match Int.of_string_opt quantity with
       | None -> Error "invalid interval quantity"
       | Some quantity ->
         (match unit_ with
          | "year" | "years" -> loop (months + (quantity * 12)) days microseconds rest
          | "mon" | "mons" | "month" | "months" ->
            loop (months + quantity) days microseconds rest
          | "day" | "days" -> loop months (days + quantity) microseconds rest
          | _ -> Error "invalid interval unit"))
    | _ -> Error "invalid interval"
  in
  loop 0 0 0L tokens
;;

let to_string value =
  let time =
    let negative = Int64.(value.microseconds < 0L) in
    let seconds = Int64.abs (Stdlib.Int64.div value.microseconds 1_000_000L) in
    let micros = Int64.abs (Stdlib.Int64.rem value.microseconds 1_000_000L) in
    let hours = Int64.(seconds / 3_600L) in
    let minutes = Int64.(seconds % 3_600L / 60L) in
    let seconds = Int64.(seconds % 60L) in
    Stdlib.Printf.sprintf
      "%s%Ld:%02Ld:%02Ld.%06Ld"
      (if negative then
         "-"
       else
         "")
      hours
      minutes
      seconds
      micros
  in
  Stdlib.Printf.sprintf "%d mons %d days %s" value.months value.days time
;;
