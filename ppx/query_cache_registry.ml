open! Base

type state =
  | Empty
  | One of Query_cache.t
  | Several

let state = ref Empty

let register queries =
  state
  := match !state with
     | Empty -> One queries
     | One _ | Several -> Several
;;

let current ~loc =
  match !state with
  | One queries -> queries
  | Empty ->
    Ppxlib.Location.raise_errorf
      ~loc
      "typed-sql-pgocaml-ppx: no query cache is registered; add the generated query-cache PPX library to (pps ...)"
  | Several ->
    Ppxlib.Location.raise_errorf
      ~loc
      "typed-sql-pgocaml-ppx: multiple query caches are registered in this PPX driver"
;;
