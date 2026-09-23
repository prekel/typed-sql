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
  | Param of parameter
  | Arithmetic of arithmetic * expr * expr
  | String_function of string_function * expr
  | Concat of expr * expr
  | Case of (condition * expr) list * expr
  | Aggregate of aggregate
  | Scalar_subquery of select
  | Current_timestamp

and parameter =
  | Value of Db_type.packed_value
  | Slot of
      { id : int
      ; db_type : Db_type.packed
      }

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

and table_source =
  { schema : Identifier.t option
  ; table : Identifier.t
  }

and relation =
  { query : select_query
  ; columns : expr list
  ; column_types : Db_type.packed list
  ; result_types : Db_type.packed list
  }

and source_kind =
  | Table of table_source
  | Derived of relation
  | Cte of int

and source =
  { source_id : int
  ; kind : source_kind
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
  { ctes : cte list
  ; source : source
  ; joins : join list
  ; distinct : bool
  ; projection : expr list
  ; where_ : condition option
  ; group_by : expr list
  ; having : condition option
  ; order_by : order list
  ; limit : pagination option
  ; offset : pagination option
  }

and select_query =
  | Simple of select
  | Compound of compound

and set_operator =
  | Union
  | Union_all
  | Intersect
  | Intersect_all
  | Except
  | Except_all

and compound =
  { ctes : cte list
  ; operator : set_operator
  ; left : select_query
  ; right : select_query
  ; left_types : Db_type.packed list
  ; right_types : Db_type.packed list
  }

and pagination =
  | Literal of int
  | Parameter of parameter

and assignment =
  { source_id : int
  ; column : Identifier.t
  ; value : assignment_value
  }

and assignment_value =
  | Expression of expr
  | Default

and command_kind =
  | Insert
  | Update
  | Delete

and conflict_target_column =
  { target_source_id : int
  ; target_column : Identifier.t
  }

and conflict =
  | Do_nothing of conflict_target_column list option
  | Do_update of
      { target : conflict_target_column list
      ; excluded_source_id : int
      ; assignments : assignment list
      ; where_ : condition option
      }

and command =
  { ctes : cte list
  ; kind : command_kind
  ; source : source
  ; assignments : assignment list
  ; rows : assignment list list
  ; from : source list
  ; conflict : conflict option
  ; where_ : condition option
  }

and returning =
  { command : command
  ; projection : expr list
  }

and materialization =
  | Materialized
  | Not_materialized

and recursion =
  | Recursive_union
  | Recursive_union_all

and cte_body =
  | Select_body of select_query
  | Recursive_body of
      { union : recursion
      ; anchor : relation
      ; step : relation
      }
  | Returning_body of returning
  | Command_body of command

and cte =
  { cte_id : int
  ; columns : expr list
  ; column_types : Db_type.packed list
  ; result_types : Db_type.packed list
  ; materialization : materialization option
  ; body : cte_body
  }

type result_query =
  | Select of select_query
  | Returning of returning
