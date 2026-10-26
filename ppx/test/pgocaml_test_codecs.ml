open! Base
include PGOCaml

let string_of_mood = string_of_string
let mood_of_string = string_of_string
let string_of_small_native = string_of_int16
let small_native_of_string = int16_of_string
let string_of_nested_native = string_of_int16
let nested_native_of_string = int16_of_string
let string_of_required_native = string_of_string
let required_native_of_string = string_of_string
let string_of_intarray_native = Typed_sql_pgocaml_runtime.string_of_array string_of_int32

let intarray_native_of_string value =
  match Typed_sql_pgocaml_runtime.array_of_string value with
  | Ok values -> List.map values ~f:(Option.map ~f:int32_of_string)
  | Error message -> Stdlib.raise (Error message)
;;
