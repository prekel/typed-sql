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
        { source_id = Nullable_table_ref.Private.source_id reference
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
  Condition.Private.create (Ast.Compare (comparison, left.node, right.node))
;;

let compare_value : type a. Ast.comparison -> a t -> a -> Condition.t =
  fun comparison left value -> compare comparison left (param left.db_type value)
;;

let eq left right = compare Ast.Eq left right
let eq_value left value = compare_value Ast.Eq left value
let neq left right = compare Ast.Neq left right
let neq_value left value = compare_value Ast.Neq left value
let lt _ left right = compare Ast.Lt left right
let lt_value _ left value = compare_value Ast.Lt left value
let lte _ left right = compare Ast.Lte left right
let lte_value _ left value = compare_value Ast.Lte left value
let gt _ left right = compare Ast.Gt left right
let gt_value _ left value = compare_value Ast.Gt left value
let gte _ left right = compare Ast.Gte left right
let gte_value _ left value = compare_value Ast.Gte left value
let like left right = compare Ast.Like left right
let like_value left value = compare_value Ast.Like left value
let is_null expression = Condition.Private.create (Ast.Is_null expression.node)
let is_not_null expression = Condition.Private.create (Ast.Is_not_null expression.node)
let db_type expression = expression.db_type

module Infix = struct
  let ( =. ) = eq
  let ( =: ) = eq_value
  let ( <>. ) = neq
  let ( <>: ) = neq_value
end

module Private = struct
  let node expression = expression.node
  let create node db_type = { node; db_type }
end
