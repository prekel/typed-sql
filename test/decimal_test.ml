open! Base
open Typed_sql

let parse_exn source =
  match Decimal.of_string source with
  | Some decimal -> decimal
  | None -> failwith ("could not parse decimal: " ^ source)
;;

let round_trip source expected =
  assert (String.equal (Decimal.to_string (parse_exn source)) expected)
;;

let%test_unit "finite decimals retain exact values" =
  List.iter
    [ "-0012.3400", "-12.34"
    ; "0.000", "0"
    ; ".0005", "0.0005"
    ; "1.25e3", "1250"
    ; "+001.0", "1"
    ; "1e+2", "100"
    ; "-5E-2", "-0.05"
    ]
    ~f:(fun (source, expected) -> round_trip source expected)
;;

let%test_unit "long trailing zero runs normalize before conversion" =
  let zeros = Stdlib.String.make 20_000 '0' in
  round_trip ("1." ^ zeros) "1";
  round_trip ("123" ^ zeros ^ "e-20000") "123";
  round_trip ("-0." ^ zeros ^ "e+20000") "0";
  assert (Decimal.equal (parse_exn ("123" ^ zeros ^ "e-20000")) (parse_exn "123"))
;;

let%test_unit "PostgreSQL numeric special values round-trip" =
  List.iter
    [ "NaN", "NaN"
    ; "Infinity", "Infinity"
    ; "+Infinity", "Infinity"
    ; "-Infinity", "-Infinity"
    ]
    ~f:(fun (source, expected) -> round_trip source expected)
;;

let%test "decimal equality uses normalized numeric values" =
  Decimal.equal (parse_exn "1e3") (parse_exn "1000")
;;

let%test "different finite and special values are unequal" =
  (not (Decimal.equal (parse_exn "1") (parse_exn "2")))
  && not (Decimal.equal (parse_exn "1") (parse_exn "-Infinity"))
;;

let%test "special values equal themselves" =
  List.for_all [ "NaN"; "Infinity"; "-Infinity" ] ~f:(fun source ->
    let value = parse_exn source in
    Decimal.equal value value)
;;

let%test_unit "malformed decimal literals are rejected" =
  List.iter
    [ "1e_2"
    ; ""
    ; "1e"
    ; "."
    ; "1.2.3"
    ; "1e999999999999999999999999"
    ; "1e" ^ Int.to_string Sys.max_string_length
    ; "1e-" ^ Int.to_string Sys.max_string_length
    ; "1.0e-" ^ Int.to_string Stdlib.max_int
    ; "10e" ^ Int.to_string Stdlib.max_int
    ; "100e" ^ Int.to_string Stdlib.max_int
    ]
    ~f:(fun source -> assert (Option.is_none (Decimal.of_string source)))
;;
