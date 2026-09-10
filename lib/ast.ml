open! Base

type expr =
  | Column of
      { source_id : int
      ; name : Identifier.t
      ; db_type : Db_type.packed
      }
  | Param of Db_type.packed_value

type comparison =
  | Eq
  | Neq
  | Lt
  | Lte
  | Gt
  | Gte
  | Like

type condition =
  | True
  | False
  | Compare of comparison * expr * expr
  | Is_null of expr
  | Is_not_null of expr
  | And of condition list
  | Or of condition list
  | Not of condition

type direction =
  | Asc
  | Desc

type order =
  { expr : expr
  ; direction : direction
  }

type source =
  { source_id : int
  ; schema : Identifier.t option
  ; table : Identifier.t
  }

type select =
  { source : source
  ; projection : expr list
  ; where_ : condition option
  ; order_by : order list
  ; limit : int option
  ; offset : int option
  }
