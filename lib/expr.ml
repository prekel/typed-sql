open! Base

type ('a, +'requirements) t =
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

let constant db_type value =
  { node = Ast.Param (Ast.Value (Db_type.Value (db_type, value))); db_type }
;;

let compare
  : type a requirements.
    Ast.comparison
    -> (a, requirements) t
    -> (a, requirements) t
    -> requirements Condition.t
  =
  fun comparison left right ->
  Condition.create (Ast.Compare (comparison, left.node, right.node))
;;

let compare_value
  : type a requirements.
    Ast.comparison -> (a, requirements) t -> a -> requirements Condition.t
  =
  fun comparison left value -> compare comparison left (constant left.db_type value)
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
  in_exprs expression (List.map values ~f:(constant expression.db_type))
;;

let not_in expression values =
  not_in_exprs expression (List.map values ~f:(constant expression.db_type))
;;

let between_exprs expression ~lower ~upper =
  Condition.create (Ast.Between (expression.node, lower.node, upper.node))
;;

let between expression ~lower ~upper =
  between_exprs
    expression
    ~lower:(constant expression.db_type lower)
    ~upper:(constant expression.db_type upper)
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

let arithmetic
  : type a requirements.
    Ast.arithmetic -> (a, requirements) t -> (a, requirements) t -> (a, requirements) t
  =
  fun operator left right ->
  { node = Ast.Arithmetic (operator, left.node, right.node); db_type = left.db_type }
;;

module type Arithmetic = sig
  type value

  val add
    :  (value, 'requirements) t
    -> (value, 'requirements) t
    -> (value, 'requirements) t

  val subtract
    :  (value, 'requirements) t
    -> (value, 'requirements) t
    -> (value, 'requirements) t

  val multiply
    :  (value, 'requirements) t
    -> (value, 'requirements) t
    -> (value, 'requirements) t

  val divide
    :  (value, 'requirements) t
    -> (value, 'requirements) t
    -> (value, 'requirements) t

  module Infix : sig
    val ( +. )
      :  (value, 'requirements) t
      -> (value, 'requirements) t
      -> (value, 'requirements) t

    val ( -. )
      :  (value, 'requirements) t
      -> (value, 'requirements) t
      -> (value, 'requirements) t

    val ( *. )
      :  (value, 'requirements) t
      -> (value, 'requirements) t
      -> (value, 'requirements) t

    val ( /. )
      :  (value, 'requirements) t
      -> (value, 'requirements) t
      -> (value, 'requirements) t
  end
end

module Arithmetic (Value : sig
    type t
  end) : Arithmetic with type value = Value.t = struct
  type value = Value.t

  let add left right = arithmetic Ast.Add left right
  let subtract left right = arithmetic Ast.Subtract left right
  let multiply left right = arithmetic Ast.Multiply left right
  let divide left right = arithmetic Ast.Divide left right

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

let concat_value left right = concat left (constant Db_type.text right)

let coalesce nullable ~default =
  { node = Ast.Coalesce (nullable.node, default.node); db_type = default.db_type }
;;

let count_all = { node = Ast.Aggregate Ast.Count_all; db_type = Db_type.int64 }

let count expression =
  { node = Ast.Aggregate (Ast.Count expression.node); db_type = Db_type.int64 }
;;

let count_distinct expression =
  { node = Ast.Aggregate (Ast.Count_distinct expression.node); db_type = Db_type.int64 }
;;

let sum_int expression =
  { node = Ast.Aggregate (Ast.Sum_int expression.node)
  ; db_type = Db_type.option Db_type.int64
  }
;;

let sum_int_nullable = sum_int

let sum_float expression =
  { node = Ast.Aggregate (Ast.Sum_float expression.node)
  ; db_type = Db_type.option Db_type.float
  }
;;

let sum_float_nullable = sum_float

let sum_int64 expression =
  { node = Ast.Aggregate (Ast.Sum_int64 expression.node)
  ; db_type = Db_type.option Db_type.numeric
  }
;;

let sum_int64_nullable = sum_int64

let sum_numeric expression =
  { node = Ast.Aggregate (Ast.Sum_numeric expression.node)
  ; db_type = Db_type.option Db_type.numeric
  }
;;

let sum_numeric_nullable = sum_numeric

let min _orderable expression =
  { node = Ast.Aggregate (Ast.Min expression.node)
  ; db_type = Db_type.option expression.db_type
  }
;;

let max _orderable expression =
  { node = Ast.Aggregate (Ast.Max expression.node)
  ; db_type = Db_type.option expression.db_type
  }
;;

let min_nullable _orderable expression =
  { node = Ast.Aggregate (Ast.Min expression.node); db_type = expression.db_type }
;;

let max_nullable _orderable expression =
  { node = Ast.Aggregate (Ast.Max expression.node); db_type = expression.db_type }
;;

let min_numeric expression = min Db_type.numeric expression
let max_numeric expression = max Db_type.numeric expression
let min_numeric_nullable expression = min_nullable Db_type.numeric expression
let max_numeric_nullable expression = max_nullable Db_type.numeric expression

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
