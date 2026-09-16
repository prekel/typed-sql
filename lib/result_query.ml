open! Base

type ('result, +'requirements) t =
  { ast : Ast.result_query
  ; projection : ('result, 'requirements) Projection.t
  }

let create ast projection = { ast; projection }
let ast query = query.ast
let projection query = query.projection
