open! Base

type source =
  | Schema of Typed_sql_schema.Schema_ir.t
  | Queries of Query_cache.t

type state =
  | Empty
  | One of source
  | Several

let state = ref Empty

let register_source source =
  state
  := match !state with
     | Empty -> One source
     | One _ | Several -> Several
;;

let register schema = register_source (Schema schema)
let register_queries queries = register_source (Queries queries)

let source ~loc =
  match !state with
  | One source -> source
  | Empty ->
    Ppxlib.Location.raise_errorf
      ~loc
      "typed-sql-pgocaml-ppx: no schema or query cache is registered; add the generated metadata PPX library to (pps ...)"
  | Several ->
    Ppxlib.Location.raise_errorf
      ~loc
      "typed-sql-pgocaml-ppx: multiple schemas or query caches are registered in this PPX driver"
;;

let current ~loc =
  match source ~loc with
  | Schema schema -> schema
  | Queries _ ->
    Ppxlib.Location.raise_errorf
      ~loc
      "typed-sql-pgocaml-ppx: a query cache is registered instead of a schema"
;;
