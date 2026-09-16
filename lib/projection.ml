open! Base

type (_, +_) t =
  | Pure_projection : 'a -> ('a, 'requirements) t
  | Expr_projection : ('a, 'requirements) Expr.t -> ('a, 'requirements) t
  | Map_projection : ('a -> 'b) * ('a, 'requirements) t -> ('b, 'requirements) t
  | Both_projection :
      ('a, 'requirements) t * ('b, 'requirements) t
      -> ('a * 'b, 'requirements) t

type 'a erased = Erased : ('a, 'requirements) t -> 'a erased

let expr expression = Expr_projection expression
let pair left right = Both_projection (expr left, expr right)

include Applicative.Make2_using_map2 (struct
    type nonrec ('a, 'requirements) t = ('a, 'requirements) t

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

    val expr : ('a, 'requirements) Expr.t -> 'a t
  end) =
struct
  let rec run_t : type a requirements. (a, requirements) t -> a A.t = function
    | Pure_projection value -> A.return value
    | Expr_projection expression -> A.expr expression
    | Map_projection (f, projection) -> A.map (run_t projection) ~f
    | Both_projection (left, right) ->
      let left = run_t left in
      let right = run_t right in
      A.both left right
  ;;

  let run (Erased projection) = run_t projection
end

let rec expressions : type a requirements. (a, requirements) t -> Ast.expr list = function
  | Pure_projection _ -> []
  | Expr_projection expression -> [ Expr.node expression ]
  | Map_projection (_, projection) -> expressions projection
  | Both_projection (left, right) -> expressions left @ expressions right
;;

let rec types : type a requirements. (a, requirements) t -> Db_type.packed list = function
  | Pure_projection _ -> []
  | Expr_projection expression -> [ Db_type.Pack (Expr.db_type expression) ]
  | Map_projection (_, projection) -> types projection
  | Both_projection (left, right) -> types left @ types right
;;

let erase projection = Erased projection
