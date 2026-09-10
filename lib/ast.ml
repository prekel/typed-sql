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

type join_kind =
  | Inner
  | Left

type join =
  { kind : join_kind
  ; source : source
  ; on : condition
  }

type select =
  { source : source
  ; joins : join list
  ; projection : expr list
  ; where_ : condition option
  ; order_by : order list
  ; limit : int option
  ; offset : int option
  }

type assignment =
  { source_id : int
  ; column : Identifier.t
  ; value : expr
  }

type command_kind =
  | Insert
  | Update
  | Delete

type command =
  { kind : command_kind
  ; source : source
  ; assignments : assignment list
  ; where_ : condition option
  }

type returning =
  { command : command
  ; projection : expr list
  }

type result_query =
  | Select of select
  | Returning of returning
