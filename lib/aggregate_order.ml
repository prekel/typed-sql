open! Base

type +'requirements t = Ast.order

let asc expression = { Ast.expr = Expr.node expression; direction = Ast.Asc }
let desc expression = { Ast.expr = Expr.node expression; direction = Ast.Desc }
let ast order = order
