open! Base

(** A parse or inference diagnostic at a byte offset in the original quotation. *)
type error = Sql_query.error =
  { offset : int (** Zero-based byte offset of the failure in the original SQL. *)
  ; message : string (** Diagnostic explanation; not a machine-readable error code. *)
  }

(** An identifier path and its original source offset. Resolution checks
    scope and ambiguity before a conversion plan is generated. *)
type reference = Sql_query.reference =
  { names : string list
    (** Identifier components in qualification order, without SQL quoting. *)
  ; offset : int (** Original byte offset of the first identifier component. *)
  }

(** One OCaml bind occurrence. [start] is inclusive and [stop] exclusive
    in the original SQL; [optional] requests nullable conversion. *)
type parameter = Sql_query.parameter =
  { expression : string
    (** OCaml expression text to splice into generated binding code. *)
  ; optional : bool (** Whether the substitution uses nullable conversion. *)
  ; start : int (** Inclusive source byte offset of the substitution. *)
  ; stop : int (** Exclusive source byte offset of the substitution. *)
  }

(** Operands supported by the legacy single-table planner. Literal
    payloads retain their source offset; values are not evaluated during parsing. *)
type operand =
  | Reference of reference (** A column reference resolved against visible sources. *)
  | Parameter_value of parameter (** An OCaml substitution supplied at runtime. *)
  | String_literal of string * int (** Decoded SQL string and its original byte offset. *)
  | Number_literal of string * int
  (** Numeric literal text and its original byte offset. *)
  | Bool_literal of bool * int (** Boolean literal and its original byte offset. *)
  | Null_literal of int (** SQL NULL at the supplied original byte offset. *)

(** Legacy predicates. Flags denote negation for null/between/in tests;
    [Like] carries negation, case-insensitivity and optional escape, while
    [Quantified] uses a final [true] flag for ANY and [false] for ALL. *)
type predicate =
  | Boolean of operand (** Boolean-valued operand used as a predicate. *)
  | Compare of string * operand * operand
  (** Comparison operator and left/right operands. *)
  | Is_null of operand * bool (** Operand and a flag selecting IS NOT NULL when true. *)
  | Like of operand * operand * bool * bool * operand option
  (** Value, pattern, NOT flag, ILIKE flag and optional escape. *)
  | Between of operand * operand * operand * bool
  (** Value, inclusive bounds and a NOT flag. *)
  | In of operand * operand list * bool (** Value, fixed candidates and a NOT flag. *)
  | Quantified of string * operand * operand * bool
  (** Operator, scalar, array and an ANY flag. *)
  | Not of predicate (** SQL boolean negation, retaining three-valued semantics. *)
  | And of predicate * predicate (** SQL conjunction of two predicates. *)
  | Or of predicate * predicate (** SQL disjunction of two predicates. *)

(** A named column, optionally renamed, or a qualified/unqualified wildcard. *)
type projection =
  | Column of reference * string option (** Column reference and optional output alias. *)
  | All of reference (** Wildcard expanded in source column order. *)

(** An INSERT/UPDATE value: substitution, source-located DEFAULT, or
    a reference to the conflicting row through EXCLUDED. *)
type value =
  | Bind of parameter (** Runtime OCaml substitution. *)
  | Default of int (** SQL DEFAULT with its original byte offset. *)
  | Excluded of reference (** A column of the row rejected by ON CONFLICT. *)

(** A target column and the value assigned to it. *)
type assignment = reference * value

(** ON CONFLICT behavior; update assignments may have a filtering predicate. *)
type conflict_action =
  | Do_nothing (** Skip a conflicting write. *)
  | Do_update of assignment list * predicate option
  (** Assignments and an optional update-filter predicate. *)

(** An optional conflict-column target and its action. Database
    constraint existence is not inferred by parsing. *)
type conflict =
  { target : reference list option
    (** Conflict columns, absent for an unspecified target. *)
  ; action : conflict_action (** Action for a conflicting row. *)
  }

(** The legacy operation shape. INSERT rows are absent for DEFAULT VALUES;
    returned fields are stored separately in the enclosing parsed statement. *)
type statement =
  | Select (** A legacy SELECT with output stored on the enclosing value. *)
  | Insert of
      { columns : reference list (** Target columns in INSERT declaration order. *)
      ; rows : value list list option (** VALUES rows, or [None] for DEFAULT VALUES. *)
      ; conflict : conflict option (** Optional ON CONFLICT clause. *)
      } (** Legacy INSERT target columns, optional VALUES rows and conflict action. *)
  | Update of assignment list (** Ordered target assignments. *)
  | Delete (** A legacy DELETE with its filter stored on the enclosing value. *)

(** A schema-qualified source with an optional alias and original byte offset. *)
type relation =
  { schema : string (** Explicit schema qualifier, without SQL quoting. *)
  ; table : string (** Source table name, without SQL quoting. *)
  ; alias : string option (** Optional query-local alias. *)
  ; offset : int (** Original source byte offset of the relation. *)
  }

(** A legacy inner join source and its ON predicate. *)
type join =
  { relation : relation (** Joined source occurrence. *)
  ; condition : predicate (** ON predicate checked in the join operand scope. *)
  }

(** A parsed quotation. [extended] selects the nested SQL representation;
    otherwise legacy fields describe a single-target statement. All offsets
    refer to [source], which retains the original quotation bytes. *)
type t =
  { source : string (** Original quotation text, before parameter rewriting. *)
  ; extended : Sql_query.statement option
    (** Nested query representation. When present, only [source] and [extended]
      are used; the legacy single-table fields are empty placeholders. *)
  ; schema : string (** Legacy target schema; unused when [extended] is present. *)
  ; table : string (** Legacy target table; unused when [extended] is present. *)
  ; alias : string option (** Legacy target alias; unused when [extended] is present. *)
  ; statement : statement
    (** Legacy operation shape; unused when [extended] is present. *)
  ; joins : join list (** Legacy inner joins in source order. *)
  ; projection : projection list (** Legacy SELECT or RETURNING output list. *)
  ; conditions : predicate option (** Legacy WHERE predicate. *)
  ; limit : operand option (** Legacy LIMIT operand. *)
  ; offset : operand option
    (** Legacy OFFSET operand, rather than a source byte offset. *)
  ; order : reference list (** Legacy ORDER BY column references in order. *)
  }

(** Parse the supported SQL subset, including joins, expressions, aggregates,
    nested SELECTs, set operations and SELECT/DML CTEs. Every token is consumed;
    offsets are bytes in the original literal. SQL strings support standard,
    escape and dollar-quoted syntax; substitutions inside them stay literal. *)
val parse : string -> (t, error) Result.t

(** Format the byte offset and diagnostic message for a parse or inference error. *)
val error_to_string : error -> string
