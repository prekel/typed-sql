open! Base

type part =
  | Text of string
  | Param of int

type t = part list

let parts template = template

let parameter_sql dialect index =
  let number = Int.to_string (index + 1) in
  match dialect with
  | Dialect.Postgresql -> "$" ^ number
  | Dialect.Sqlite -> "?" ^ number
;;

let to_sql ~dialect template =
  List.map template ~f:(function
    | Text text -> text
    | Param index -> parameter_sql dialect index)
  |> String.concat
;;

module Private = struct
  let of_parts parts = parts

  let shape_string template =
    List.map template ~f:(function
      | Text text -> text
      | Param index -> "${" ^ Int.to_string index ^ "}")
    |> String.concat
  ;;
end
