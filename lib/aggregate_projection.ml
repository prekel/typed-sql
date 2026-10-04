open! Base

type ('a, +'requirements) t = ('a, 'requirements) Projection.t

let projection value = value
let map value ~f = Projection.map value ~f
let both left right = Projection.both left right

module Let_syntax = struct
  module Let_syntax = struct
    let map = map
    let both = both

    module Open_on_rhs = struct end
  end
end

let count_all = Projection.expr Expr.count_all
let count expression = Projection.expr (Expr.count expression)
let count_distinct expression = Projection.expr (Expr.count_distinct expression)
let sum_int expression = Projection.expr (Expr.sum_int expression)
let sum_int_nullable expression = Projection.expr (Expr.sum_int_nullable expression)
let sum_float expression = Projection.expr (Expr.sum_float expression)
let sum_float_nullable expression = Projection.expr (Expr.sum_float_nullable expression)
let min witness expression = Projection.expr (Expr.min witness expression)
let max witness expression = Projection.expr (Expr.max witness expression)

let min_nullable witness expression =
  Projection.expr (Expr.min_nullable witness expression)
;;

let max_nullable witness expression =
  Projection.expr (Expr.max_nullable witness expression)
;;

let multiset_agg ?filter ?order_by projection =
  Projection.multiset_agg ?filter ?order_by projection
;;

let sum_int64 expression = Projection.expr (Expr.sum_int64 expression)
let sum_int64_nullable expression = Projection.expr (Expr.sum_int64_nullable expression)
let sum_numeric expression = Projection.expr (Expr.sum_numeric expression)

let sum_numeric_nullable expression =
  Projection.expr (Expr.sum_numeric_nullable expression)
;;

let min_numeric expression = Projection.expr (Expr.min_numeric expression)
let max_numeric expression = Projection.expr (Expr.max_numeric expression)

let min_numeric_nullable expression =
  Projection.expr (Expr.min_numeric_nullable expression)
;;

let max_numeric_nullable expression =
  Projection.expr (Expr.max_numeric_nullable expression)
;;

let avg_int expression = Projection.expr (Expr.avg_int expression)
let avg_int_nullable expression = Projection.expr (Expr.avg_int_nullable expression)
let avg_int64 expression = Projection.expr (Expr.avg_int64 expression)
let avg_int64_nullable expression = Projection.expr (Expr.avg_int64_nullable expression)
let avg_float expression = Projection.expr (Expr.avg_float expression)
let avg_float_nullable expression = Projection.expr (Expr.avg_float_nullable expression)
let avg_int_numeric expression = Projection.expr (Expr.avg_int_numeric expression)

let avg_int_numeric_nullable expression =
  Projection.expr (Expr.avg_int_numeric_nullable expression)
;;

let avg_int64_numeric expression = Projection.expr (Expr.avg_int64_numeric expression)

let avg_int64_numeric_nullable expression =
  Projection.expr (Expr.avg_int64_numeric_nullable expression)
;;

let avg_numeric expression = Projection.expr (Expr.avg_numeric expression)

let avg_numeric_nullable expression =
  Projection.expr (Expr.avg_numeric_nullable expression)
;;
