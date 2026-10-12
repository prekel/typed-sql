open! Base

type kind =
  | Unique
  | Foreign_key
  | Not_null
  | Check
  | Restrict
  | Exclusion
  | Other

type t =
  { kind : kind
  ; message : string
  ; sqlstate : string option
  ; constraint_name : string option
  ; schema_name : string option
  ; table_name : string option
  ; column_name : string option
  ; detail : string option
  ; hint : string option
  }

let create
      ?sqlstate
      ?constraint_name
      ?schema_name
      ?table_name
      ?column_name
      ?detail
      ?hint
      ~kind
      ~message
      ()
  =
  { kind
  ; message
  ; sqlstate
  ; constraint_name
  ; schema_name
  ; table_name
  ; column_name
  ; detail
  ; hint
  }
;;

let equal_kind left right =
  match left, right with
  | Unique, Unique
  | Foreign_key, Foreign_key
  | Not_null, Not_null
  | Check, Check
  | Restrict, Restrict
  | Exclusion, Exclusion
  | Other, Other -> true
  | _ -> false
;;

let matches ?kind ?constraint_name ?schema_name ?table_name ?column_name error =
  let reported expected actual =
    Option.for_all expected ~f:(fun expected ->
      Option.value_map actual ~default:false ~f:(String.equal expected))
  in
  Option.for_all kind ~f:(equal_kind error.kind)
  && reported constraint_name error.constraint_name
  && reported schema_name error.schema_name
  && reported table_name error.table_name
  && reported column_name error.column_name
;;

let to_string error =
  let kind =
    match error.kind with
    | Unique -> "unique"
    | Foreign_key -> "foreign key"
    | Not_null -> "not null"
    | Check -> "check"
    | Restrict -> "restrict"
    | Exclusion -> "exclusion"
    | Other -> "integrity"
  in
  Stdlib.Printf.sprintf "%s constraint violation: %s" kind error.message
;;
