open! Base

type error =
  { offset : int
  ; message : string
  }

type reference =
  { names : string list
  ; offset : int
  }

type parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type kind =
  | Word of string
  | Quoted of string
  | Symbol of char
  | Parameter of parameter
  | String_sql of string
  | Number of string
  | Operator of string
  | End

type token =
  { kind : kind
  ; offset : int
  }

type type_name =
  { names : string list
  ; dimensions : int
  ; modified : bool
  }

type expression =
  { node : expression_node
  ; offset : int
  }

and expression_node =
  | Column of string list
  | Parameter_value of parameter
  | String_literal of string
  | Number_literal of string
  | Bool_literal of bool
  | Null_literal
  | Default
  | Unary of string * expression
  | Binary of string * expression * expression
  | Cast of expression * type_name
  | Case of expression option * (expression * expression) list * expression option
  | Call of call
  | Like_escape of expression * expression
  | Is_null of expression * bool
  | Between of expression * expression * expression * bool
  | In_list of expression * expression list * bool
  | In_query of expression * statement * bool
  | Quantified of string * expression * expression * bool
  | Scalar of statement
  | Exists of statement

and call =
  { name : string list
  ; args : expression list
  ; star : bool
  ; distinct : bool
  ; order : ordering list
  ; filter : expression option
  }

and ordering = expression * bool * bool option

and projection =
  | Field of expression * string option
  | All of reference

and relation =
  { relation : relation_node
  ; alias : string option
  ; columns : string list
  ; offset : int
  }

and relation_node =
  | Table of reference
  | Derived of statement
  | Join of relation * relation * join_kind * join_condition

and join_kind =
  | Inner
  | Left
  | Right
  | Full
  | Cross

and join_condition =
  | On of expression
  | Using of reference list
  | Natural
  | No_condition

and select =
  { projection : projection list
  ; from : relation option
  ; conditions : expression option
  ; group : expression list
  ; having : expression option
  ; distinct : bool
  }

and conflict =
  { target : reference list option
  ; action : conflict_action
  }

and conflict_action =
  | Do_nothing
  | Do_update of assignment list * expression option

and assignment = reference * expression

and body =
  | Select of select
  | Set of string * bool * statement * statement
  | Nested of statement
  | Insert of
      reference
      * string option
      * reference list
      * expression list list option
      * statement option
      * conflict option
      * projection list
  | Update of
      reference * string option * assignment list * expression option * projection list
  | Delete of reference * string option * expression option * projection list

and cte =
  { name : string
  ; columns : string list
  ; query : statement
  ; offset : int
  }

and statement =
  { ctes : cte list
  ; recursive : bool
  ; body : body
  ; order : ordering list
  ; limit : expression option
  ; pagination_offset : expression option
  ; offset : int
  }

(** Tokenize SQL without interpreting substitutions inside strings or comments. *)
val lex : string -> (token list, error) Result.t

(** Parse nested SQL; all offsets refer to the original source literal. *)
val parse : token list -> (statement, error) Result.t
