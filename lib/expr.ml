open! Base

type 'a t =
  { node : Ast.expr
  ; db_type : 'a Db_type.t
  }

let column reference column =
  { node =
      Ast.Column
        { source_id = Table_ref.source_id reference
        ; name = Column.name column
        ; db_type = Db_type.Pack (Column.db_type column)
        }
  ; db_type = Column.db_type column
  }
;;

let nullable_column reference column =
  let db_type = Db_type.option (Column.base_db_type column) in
  { node =
      Ast.Column
        { source_id = Nullable_table_ref.source_id reference
        ; name = Column.name column
        ; db_type = Db_type.Pack db_type
        }
  ; db_type
  }
;;

let to_nullable expression =
  { node = expression.node; db_type = Db_type.option expression.db_type }
;;

let param db_type value = { node = Ast.Param (Db_type.Value (db_type, value)); db_type }

let compare : type a. Ast.comparison -> a t -> a t -> Condition.t =
  fun comparison left right ->
  Condition.create (Ast.Compare (comparison, left.node, right.node))
;;

let compare_value : type a. Ast.comparison -> a t -> a -> Condition.t =
  fun comparison left value -> compare comparison left (param left.db_type value)
;;

let eq left right = compare Ast.Eq left right
let eq_value left value = compare_value Ast.Eq left value
let neq left right = compare Ast.Neq left right
let neq_value left value = compare_value Ast.Neq left value
let like left right = compare Ast.Like left right
let like_value left value = compare_value Ast.Like left value
let is_null expression = Condition.create (Ast.Is_null expression.node)
let is_not_null expression = Condition.create (Ast.Is_not_null expression.node)

let in_exprs expression values =
  Condition.create
    (Ast.In (expression.node, List.map values ~f:(fun value -> value.node)))
;;

let not_in_exprs expression values =
  Condition.create
    (Ast.Not_in (expression.node, List.map values ~f:(fun value -> value.node)))
;;

let in_ expression values =
  in_exprs expression (List.map values ~f:(param expression.db_type))
;;

let not_in expression values =
  not_in_exprs expression (List.map values ~f:(param expression.db_type))
;;

let between_exprs expression ~lower ~upper =
  Condition.create (Ast.Between (expression.node, lower.node, upper.node))
;;

let between expression ~lower ~upper =
  between_exprs
    expression
    ~lower:(param expression.db_type lower)
    ~upper:(param expression.db_type upper)
;;

let is_distinct_from left right = compare Ast.Is_distinct_from left right
let is_distinct_from_value left right = compare_value Ast.Is_distinct_from left right

let case branches ~else_ =
  { node =
      Ast.Case
        ( List.map branches ~f:(fun (condition, expression) ->
            Condition.node condition, expression.node)
        , else_.node )
  ; db_type = else_.db_type
  }
;;

let arithmetic operator left right =
  { node = Ast.Arithmetic (operator, left.node, right.node); db_type = left.db_type }
;;

module type Arithmetic = sig
  type value

  val add : value t -> value t -> value t
  val subtract : value t -> value t -> value t
  val multiply : value t -> value t -> value t
  val divide : value t -> value t -> value t

  module Infix : sig
    val ( +. ) : value t -> value t -> value t
    val ( -. ) : value t -> value t -> value t
    val ( *. ) : value t -> value t -> value t
    val ( /. ) : value t -> value t -> value t
  end
end

module Arithmetic (Value : sig
    type t
  end) : Arithmetic with type value = Value.t = struct
  type value = Value.t

  let add = arithmetic Ast.Add
  let subtract = arithmetic Ast.Subtract
  let multiply = arithmetic Ast.Multiply
  let divide = arithmetic Ast.Divide

  module Infix = struct
    let ( +. ) = add
    let ( -. ) = subtract
    let ( *. ) = multiply
    let ( /. ) = divide
  end
end

module Int = Arithmetic (Int)
module Int64 = Arithmetic (Int64)
module Float = Arithmetic (Float)

let lower expression =
  { node = Ast.String_function (Ast.Lower, expression.node); db_type = Db_type.text }
;;

let upper expression =
  { node = Ast.String_function (Ast.Upper, expression.node); db_type = Db_type.text }
;;

let length expression =
  { node = Ast.String_function (Ast.Length, expression.node); db_type = Db_type.int }
;;

let concat left right =
  { node = Ast.Concat (left.node, right.node); db_type = Db_type.text }
;;

let concat_value left right = concat left (param Db_type.text right)
let count_all = { node = Ast.Aggregate Ast.Count_all; db_type = Db_type.int64 }

let count expression =
  { node = Ast.Aggregate (Ast.Count expression.node); db_type = Db_type.int64 }
;;

let count_distinct expression =
  { node = Ast.Aggregate (Ast.Count_distinct expression.node); db_type = Db_type.int64 }
;;

let scalar_subquery query =
  { node = Ast.Scalar_subquery (Scalar_query.ast query)
  ; db_type = Db_type.option (Scalar_query.db_type query)
  }
;;

let scalar_subquery_nullable query =
  { node = Ast.Scalar_subquery (Scalar_query.ast query)
  ; db_type = Scalar_query.db_type query
  }
;;

let current_timestamp = { node = Ast.Current_timestamp; db_type = Db_type.timestamp }
let db_type expression = expression.db_type

module Infix = struct
  let ( =. ) = eq
  let ( <>. ) = neq
  let ( <. ) left right = compare Ast.Lt left right
  let ( <=. ) left right = compare Ast.Lte left right
  let ( >. ) left right = compare Ast.Gt left right
  let ( >=. ) left right = compare Ast.Gte left right
  let ( =$ ) = eq_value
  let ( <>$ ) = neq_value
  let ( <$ ) left value = compare_value Ast.Lt left value
  let ( <=$ ) left value = compare_value Ast.Lte left value
  let ( >$ ) left value = compare_value Ast.Gt left value
  let ( >=$ ) left value = compare_value Ast.Gte left value
  let ( =~. ) = like
  let ( =~$ ) = like_value
end

let node expression = expression.node
let create node db_type = { node; db_type }
