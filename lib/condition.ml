open! Base

type t = Ast.condition

let true_ = Ast.True
let false_ = Ast.False
let and_ left right = Ast.And [ left; right ]
let or_ left right = Ast.Or [ left; right ]
let not_ condition = Ast.Not condition
let all conditions = Ast.And conditions
let any conditions = Ast.Or conditions

module Infix = struct
  let ( &&. ) = and_
  let ( ||. ) = or_
end

module Private = struct
  let create condition = condition
  let node condition = condition
end
