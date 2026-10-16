open! Base

type select
type returning

type ('result, 'kind, +'cardinality, +'requirements) t =
  { ast : Ast.result_query
  ; projection : ('result, 'requirements) Projection.t
  ; requires_exactly_one : bool
  }

let create_select ?(requires_exactly_one = false) ast projection =
  { ast = Ast.Select ast; projection; requires_exactly_one }
;;

let create_returning returning projection =
  { ast = Ast.Returning returning; projection; requires_exactly_one = false }
;;

let create_raw_returning raw projection =
  { ast = Ast.Raw_returning raw; projection; requires_exactly_one = false }
;;

let ast query = query.ast
let projection query = query.projection
let requires_exactly_one query = query.requires_exactly_one
let with_ast query ast = { query with ast }
