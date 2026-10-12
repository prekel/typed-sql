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
      Z.minus_one, String.drop_prefix value 1
    else if String.is_prefix value ~prefix:"+" then
      Z.one, String.drop_prefix value 1
    else
      Z.one, value
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
       when Int64.(
              hours >= 0L
              && minutes >= 0L
              && minutes < 60L
              && seconds >= 0L
              && seconds < 60L)
            && Int.(String.length fraction <= 6)
            && String.for_all fraction ~f:Char.is_digit ->
       let fraction = fraction ^ String.make (6 - String.length fraction) '0' in
       Option.bind (parse fraction) ~f:(fun micros ->
         let total =
           Z.(
             direction
             * ((((((of_int64 hours * of_int 60) + of_int64 minutes) * of_int 60)
                  + of_int64 seconds)
                 * of_int 1_000_000)
                + of_int64 micros))
         in
         if Z.fits_int64 total then
           Some (Z.to_int64 total)
         else
           None)
     | _ -> None)
  | _ -> None
;;

let of_string source =
  let tokens =
    String.split (String.strip source) ~on:' '
    |> List.filter ~f:(fun token -> not (String.is_empty token))
  in
  let rec loop months days microseconds tokens =
    if not (Z.fits_int months && Z.fits_int days && Z.fits_int64 microseconds) then
      Error "interval overflow"
    else (
      match
        tokens
      with
      | [] ->
        Ok
          { months = Z.to_int months
          ; days = Z.to_int days
          ; microseconds = Z.to_int64 microseconds
          }
      | [ "ago" ] -> loop (Z.neg months) (Z.neg days) (Z.neg microseconds) []
      | time :: rest when String.mem time ':' ->
        (match time_to_microseconds time with
         | Some time -> loop months days Z.(microseconds + of_int64 time) rest
         | None -> Error "invalid interval time")
      | quantity :: unit_ :: rest ->
        (match Int.of_string_opt quantity with
         | None -> Error "invalid interval quantity"
         | Some quantity ->
           (match unit_ with
            | "year" | "years" ->
              loop Z.(months + (of_int quantity * of_int 12)) days microseconds rest
            | "mon" | "mons" | "month" | "months" ->
              loop Z.(months + of_int quantity) days microseconds rest
            | "day" | "days" -> loop months Z.(days + of_int quantity) microseconds rest
            | _ -> Error "invalid interval unit"))
      | _ -> Error "invalid interval")
  in
  loop Z.zero Z.zero Z.zero tokens
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
