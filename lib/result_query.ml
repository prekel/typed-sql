open! Base

type 'result t =
  { ast : Ast.result_query
  ; projection : 'result Projection.t
  }

module Private = struct
  let create ast projection = { ast; projection }
  let ast query = query.ast
  let projection query = query.projection
end
