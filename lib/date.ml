open! Base

type t = Ptime.t

let of_ymd ~year ~month ~day = Ptime.of_date (year, month, day)

let of_ymd_exn ~year ~month ~day =
  match of_ymd ~year ~month ~day with
  | Some date -> date
  | None -> Stdlib.invalid_arg "invalid calendar date"
;;

let to_ymd value = Ptime.to_date value
let of_ptime value = Ptime.of_date (Ptime.to_date value) |> Option.value_exn
let to_ptime value = value

let to_string value =
  let year, month, day = to_ymd value in
  Stdlib.Printf.sprintf "%04d-%02d-%02d" year month day
;;

let of_string value =
  if
    Int.(String.length value = 10)
    && Char.equal value.[4] '-'
    && Char.equal value.[7] '-'
    && String.for_alli value ~f:(fun index character ->
      Int.(index = 4 || index = 7) || Char.is_digit character)
  then (
    let year = Int.of_string (String.sub value ~pos:0 ~len:4) in
    let month = Int.of_string (String.sub value ~pos:5 ~len:2) in
    let day = Int.of_string (String.sub value ~pos:8 ~len:2) in
    of_ymd ~year ~month ~day)
  else
    None
;;

let equal = Ptime.equal
