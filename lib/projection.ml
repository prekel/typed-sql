open! Base

type _ t =
  | Pure_projection : 'a -> 'a t
  | Expr_projection : 'a Expr.t -> 'a t
  | Map_projection : ('a -> 'b) * 'a t -> 'b t
  | Both_projection : 'a t * 'b t -> ('a * 'b) t

type _ view =
  | Pure : 'a -> 'a view
  | Expr : 'a Expr.t -> 'a view
  | Map : ('a -> 'b) * 'a t -> 'b view
  | Both : 'a t * 'b t -> ('a * 'b) view

let pure value = Pure_projection value
let expr expression = Expr_projection expression
let map function_ projection = Map_projection (function_, projection)
let both left right = Both_projection (left, right)

let map2 function_ left right =
  both left right |> map (fun (left, right) -> function_ left right)
;;

let map3 function_ first second third =
  both (both first second) third
  |> map (fun ((first, second), third) -> function_ first second third)
;;

let view : type a. a t -> a view = function
  | Pure_projection value -> Pure value
  | Expr_projection expression -> Expr expression
  | Map_projection (function_, projection) -> Map (function_, projection)
  | Both_projection (left, right) -> Both (left, right)
;;

module Private = struct
  let rec expressions : type a. a t -> Ast.expr list = function
    | Pure_projection _ -> []
    | Expr_projection expression -> [ Expr.Private.node expression ]
    | Map_projection (_, projection) -> expressions projection
    | Both_projection (left, right) -> expressions left @ expressions right
  ;;
end
