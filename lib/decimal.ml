open! Base

type t =
  | Finite of Z.t * int
  | NaN
  | Positive_infinity
  | Negative_infinity

let of_string source =
  match String.lowercase source with
  | "nan" -> Some NaN
  | "infinity" | "+infinity" -> Some Positive_infinity
  | "-infinity" -> Some Negative_infinity
  | _ ->
    let length = String.length source in
    if Int.(length = 0) then
      None
    else (
      let start, sign =
        match source.[0] with
        | '-' -> 1, -1
        | '+' -> 1, 1
        | _ -> 0, 1
      in
      let parse_exponent index =
        let sign, start =
          if Int.(index < length) then (
            match
              source.[index]
            with
            | '-' -> -1, index + 1
            | '+' -> 1, index + 1
            | _ -> 1, index)
          else
            1, index
        in
        if Int.(start = length) then
          None
        else (
          let rec digits index value =
            if Int.(index = length) then
              Some (sign * value)
            else (
              match
                source.[index]
              with
              | '0' .. '9' as digit ->
                let digit = Char.to_int digit - Char.to_int '0' in
                if value > (Stdlib.max_int - digit) / 10 then
                  None
                else
                  digits (index + 1) ((value * 10) + digit)
              | _ -> None)
          in
          digits start 0)
      in
      let rec parse_digits index seen_dot digit_count fractional collected =
        if Int.(index = length) then
          if Int.(digit_count = 0) then
            None
          else
            Some (collected, fractional, 0)
        else (
          match
            source.[index]
          with
          | '0' .. '9' as digit ->
            parse_digits
              (index + 1)
              seen_dot
              (digit_count + 1)
              (fractional
               +
               if seen_dot then
                 1
               else
                 0)
              (digit :: collected)
          | '.' when not seen_dot ->
            parse_digits (index + 1) true digit_count fractional collected
          | ('e' | 'E') when Int.(digit_count > 0) ->
            Option.map
              (parse_exponent (index + 1))
              ~f:(fun exponent -> collected, fractional, exponent)
          | _ -> None)
      in
      match parse_digits start false 0 0 [] with
      | None -> None
      | Some (reversed_digits, fractional, exponent) ->
        let scale =
          if exponent < 0 && fractional > Stdlib.max_int + exponent then
            None
          else
            Some (fractional - exponent)
        in
        Option.bind scale ~f:(fun scale ->
          let rec strip_trailing_zeros count = function
            | '0' :: rest -> strip_trailing_zeros (count + 1) rest
            | digits -> count, digits
          in
          let trailing_zeros, reversed_digits = strip_trailing_zeros 0 reversed_digits in
          if List.is_empty reversed_digits then
            Some (Finite (Z.zero, 0))
          else if scale < Stdlib.min_int + trailing_zeros then
            None
          else (
            let scale = scale - trailing_zeros in
            let digits = List.rev reversed_digits |> String.of_char_list in
            let coefficient = Z.of_string digits in
            let coefficient =
              if Int.equal sign (-1) then
                Z.neg coefficient
              else
                coefficient
            in
            let digit_count = String.length (Z.to_string (Z.abs coefficient)) in
            let sign_length =
              if Z.sign coefficient < 0 then
                1
              else
                0
            in
            let formatted_length =
              if scale <= 0 then (
                let available = Sys.max_string_length - digit_count - sign_length in
                if scale < -available then
                  None
                else
                  Some (digit_count - scale + sign_length))
              else if scale >= digit_count then
                if scale > Sys.max_string_length - 2 - sign_length then
                  None
                else
                  Some (scale + 2 + sign_length)
              else
                Some (digit_count + 1 + sign_length)
            in
            match formatted_length with
            | Some length when length <= Sys.max_string_length ->
              Some (Finite (coefficient, scale))
            | _ -> None)))
;;

let to_string = function
  | NaN -> "NaN"
  | Positive_infinity -> "Infinity"
  | Negative_infinity -> "-Infinity"
  | Finite (coefficient, scale) ->
    let negative = Z.sign coefficient < 0 in
    let digits = Z.to_string (Z.abs coefficient) in
    let magnitude =
      if scale <= 0 then
        digits ^ Stdlib.String.make (-scale) '0'
      else if scale >= String.length digits then
        "0." ^ Stdlib.String.make (scale - String.length digits) '0' ^ digits
      else (
        let split = String.length digits - scale in
        String.sub digits ~pos:0 ~len:split
        ^ "."
        ^ String.sub digits ~pos:split ~len:scale)
    in
    if negative then
      "-" ^ magnitude
    else
      magnitude
;;

let equal left right =
  match left, right with
  | Finite (left, left_scale), Finite (right, right_scale) ->
    Z.equal left right && Int.equal left_scale right_scale
  | NaN, NaN | Positive_infinity, Positive_infinity | Negative_infinity, Negative_infinity
    -> true
  | _ -> false
;;
