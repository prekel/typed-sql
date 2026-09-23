open! Base

type select
type returning

type ('result, 'kind, +'requirements) t =
  { ast : Ast.result_query
  ; projection : ('result, 'requirements) Projection.t
  }

let create_select ast projection = { ast = Ast.Select ast; projection }
let create_returning returning projection = { ast = Ast.Returning returning; projection }
let ast query = query.ast
let projection query = query.projection
let with_ast query ast = { query with ast }
