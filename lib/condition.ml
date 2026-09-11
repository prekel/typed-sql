open! Base

type t = Ast.condition

let true_ = Ast.True
let false_ = Ast.False
let and_ left right = Ast.And [ left; right ]
let or_ left right = Ast.Or [ left; right ]
let not_ condition = Ast.Not condition

module Infix = struct
  let ( &&. ) = and_
  let ( ||. ) = or_
end

let create condition = condition
let node condition = condition
