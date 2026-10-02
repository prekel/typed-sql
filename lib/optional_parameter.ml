open! Base

type ('value, +'requirements) t =
  { nullable_expr : ('value option, 'requirements) Expr.t
  ; value_expr : ('value, 'requirements) Expr.t
  }

let create nullable_expr value_expr = { nullable_expr; value_expr }
let nullable_expr parameter = parameter.nullable_expr
let value_expr parameter = parameter.value_expr
