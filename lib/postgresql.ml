open! Base

let string_agg_node ?(order_by = []) ~delimiter value =
  Ast.Aggregate
    (Ast.String_agg
       { value = Expr.node value
       ; delimiter = Expr.node delimiter
       ; order_by = List.map order_by ~f:Aggregate_order.ast
       })
;;

let string_agg ?order_by ~delimiter value =
  Expr.create (string_agg_node ?order_by ~delimiter value) (Db_type.option Db_type.text)
;;

let string_agg_nullable ?order_by ~delimiter value =
  Expr.create (string_agg_node ?order_by ~delimiter value) (Db_type.option Db_type.text)
;;
