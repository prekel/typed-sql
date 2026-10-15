open! Base

type error = Sql_query.error =
  { offset : int
  ; message : string
  }

type reference = Sql_query.reference =
  { names : string list
  ; offset : int
  }

type parameter = Sql_query.parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type operand =
  | Reference of reference
  | Parameter_value of parameter
  | String_literal of string * int
  | Number_literal of string * int
  | Bool_literal of bool * int
  | Null_literal of int

type predicate =
  | Boolean of operand
  | Compare of string * operand * operand
  | Is_null of operand * bool
  | Like of operand * operand * bool * bool * operand option
  | Between of operand * operand * operand * bool
  | In of operand * operand list * bool
  | Quantified of string * operand * operand * bool
  | Not of predicate
  | And of predicate * predicate
  | Or of predicate * predicate

type projection =
  | Column of reference * string option
  | All of reference

type value =
  | Bind of parameter
  | Default of int
  | Excluded of reference

type assignment = reference * value

type conflict_action =
  | Do_nothing
  | Do_update of assignment list * predicate option

type conflict =
  { target : reference list option
  ; action : conflict_action
  }

type statement =
  | Select
  | Insert of
      { columns : reference list
      ; rows : value list list option
      ; conflict : conflict option
      }
  | Update of assignment list
  | Delete

type relation =
  { schema : string
  ; table : string
  ; alias : string option
  ; offset : int
  }

type join =
  { relation : relation
  ; condition : predicate
  }

type t =
  { source : string
  ; extended : Sql_query.statement option
    (** Nested query representation. When present, only [source] and [extended]
      are used; the legacy single-table fields are empty placeholders. *)
  ; schema : string
  ; table : string
  ; alias : string option
  ; statement : statement
  ; joins : join list
  ; projection : projection list
  ; conditions : predicate option
  ; limit : operand option
  ; offset : operand option
  ; order : reference list
  }

(** Parse the supported SQL subset, including joins, expressions, aggregates,
    nested SELECTs, set operations and SELECT/DML CTEs. Every token is consumed;
    offsets are bytes in the original literal. SQL strings use standard
    conforming string syntax. *)
val parse : string -> (t, error) Result.t

val error_to_string : error -> string
