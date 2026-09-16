open! Base

type ('a, +'requirements) t =
  { ast : Ast.select
  ; db_type : 'a Db_type.t
  }

let create ast db_type = { ast; db_type }
let ast query = query.ast
let db_type query = query.db_type
