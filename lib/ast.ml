open! Base

type arithmetic =
  | Add
  | Subtract
  | Multiply
  | Divide

type string_function =
  | Lower
  | Upper
  | Length
  | Sqlite_length

type aggregate =
  | Count_all
  | Count of expr
  | Count_distinct of expr

and expr =
  | Column of
      { source_id : int
      ; name : Identifier.t
      ; db_type : Db_type.packed
      }
  | Param of Db_type.packed_value
  | Arithmetic of arithmetic * expr * expr
  | String_function of string_function * expr
  | Concat of expr * expr
  | Case of (condition * expr) list * expr
  | Aggregate of aggregate
  | Scalar_subquery of select
  | Current_timestamp

and comparison =
  | Eq
  | Neq
  | Lt
  | Lte
  | Gt
  | Gte
  | Like
  | Is_distinct_from
  | Sqlite_is_not

and condition =
  | True
  | False
  | Compare of comparison * expr * expr
  | Is_null of expr
  | Is_not_null of expr
  | In of expr * expr list
  | Not_in of expr * expr list
  | Between of expr * expr * expr
  | Exists of select
  | Not_exists of select
  | In_subquery of expr * select
  | Not_in_subquery of expr * select
  | And of condition list
  | Or of condition list
  | Not of condition

and direction =
  | Asc
  | Desc

and order =
  { expr : expr
  ; direction : direction
  }

and source =
  { source_id : int
  ; schema : Identifier.t option
  ; table : Identifier.t
  }

and join_kind =
  | Inner
  | Left

and join =
  { kind : join_kind
  ; source : source
  ; on : condition
  }

and select =
  { source : source
  ; joins : join list
  ; distinct : bool
  ; projection : expr list
  ; where_ : condition option
  ; group_by : expr list
  ; having : condition option
  ; order_by : order list
  ; limit : int option
  ; offset : int option
  }

type assignment =
  { source_id : int
  ; column : Identifier.t
  ; value : assignment_value
  }

and assignment_value =
  | Expression of expr
  | Default

type command_kind =
  | Insert
  | Update
  | Delete

type conflict = Do_nothing

type command =
  { kind : command_kind
  ; source : source
  ; assignments : assignment list
  ; rows : assignment list list
  ; from : source list
  ; conflict : conflict option
  ; where_ : condition option
  }

type returning =
  { command : command
  ; projection : expr list
  }

type result_query =
  | Select of select
  | Returning of returning
