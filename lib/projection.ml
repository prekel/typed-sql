open! Base

type _ t =
  | Pure_projection : 'a -> 'a t
  | Expr_projection : 'a Expr.t -> 'a t
  | Map_projection : ('a -> 'b) * 'a t -> 'b t
  | Both_projection : 'a t * 'b t -> ('a * 'b) t

let expr expression = Expr_projection expression
let pair left right = Both_projection (expr left, expr right)

include Applicative.Make_using_map2 (struct
    type nonrec 'a t = 'a t

    let return value = Pure_projection value
    let map projection ~f = Map_projection (f, projection)
    let map2 left right ~f = map (Both_projection (left, right)) ~f:(fun (a, b) -> f a b)
    let map = `Custom map
  end)

module Let_syntax = struct
  let return = return

  include Applicative_infix

  module Let_syntax = struct
    let return = return
    let map = map
    let both = both

    module Open_on_rhs = struct end
  end
end

module Make (A : sig
    include Applicative.S

    val expr : 'a Expr.t -> 'a t
  end) =
struct
  let rec run : type a. a t -> a A.t = function
    | Pure_projection value -> A.return value
    | Expr_projection expression -> A.expr expression
    | Map_projection (f, projection) -> A.map (run projection) ~f
    | Both_projection (left, right) ->
      let left = run left in
      let right = run right in
      A.both left right
  ;;
end

let rec expressions : type a. a t -> Ast.expr list = function
  | Pure_projection _ -> []
  | Expr_projection expression -> [ Expr.node expression ]
  | Map_projection (_, projection) -> expressions projection
  | Both_projection (left, right) -> expressions left @ expressions right
;;

let rec types : type a. a t -> Db_type.packed list = function
  | Pure_projection _ -> []
  | Expr_projection expression -> [ Db_type.Pack (Expr.db_type expression) ]
  | Map_projection (_, projection) -> types projection
  | Both_projection (left, right) -> types left @ types right
;;
