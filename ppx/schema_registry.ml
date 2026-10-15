open! Base

type state =
  | Empty
  | One of Typed_sql_schema.Schema_ir.t
  | Several

let state = ref Empty

let register schema =
  state
  := match !state with
     | Empty -> One schema
     | One _ | Several -> Several
;;

let current ~loc =
  match !state with
  | One schema -> schema
  | Empty ->
    Ppxlib.Location.raise_errorf
      ~loc
      "typed-sql-pgocaml-ppx: no schema is registered; add the generated schema PPX library to (pps ...)"
  | Several ->
    Ppxlib.Location.raise_errorf
      ~loc
      "typed-sql-pgocaml-ppx: multiple schemas are registered in this PPX driver"
;;
