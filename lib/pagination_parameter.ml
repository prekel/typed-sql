open! Base

type +'requirements t = Ast.parameter
type +'requirements optional = Ast.parameter

let create parameter = parameter
let node parameter = parameter
let create_optional parameter = parameter
let optional_node parameter = parameter
