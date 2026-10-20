open! Base

(** A diagnostic with a zero-based byte offset in the original SQL literal. *)
type error =
  { offset : int (** Zero-based byte offset of the failure in the original SQL. *)
  ; message : string (** Diagnostic explanation; not a machine-readable error code. *)
  }

(** An SQL identifier path with its original source offset. *)
type reference =
  { names : string list
    (** Identifier components in qualification order, without SQL quoting. *)
  ; offset : int (** Original byte offset of the first identifier component. *)
  }

(** An OCaml substitution with an inclusive start and exclusive stop
    byte offset in the original SQL. [optional] requests option conversion. *)
type parameter =
  { expression : string
    (** OCaml expression text to splice into generated binding code. *)
  ; optional : bool (** Whether the substitution uses nullable conversion. *)
  ; start : int (** Inclusive source byte offset of the substitution. *)
  ; stop : int (** Exclusive source byte offset of the substitution. *)
  }

(** Lexical token kinds. Quoted identifiers remain distinct from words;
    SQL strings are decoded without interpreting OCaml substitutions within them. *)
type kind =
  | Word of string (** Unquoted word normalized by the lexer. *)
  | Quoted of string (** Decoded quoted identifier with case preserved. *)
  | Symbol of char (** Single-character punctuation. *)
  | Parameter of parameter (** An OCaml substitution outside SQL strings and comments. *)
  | String_sql of string (** Decoded SQL string literal. *)
  | Number of string
  (** SQL numeric literal text without conversion to an OCaml number. *)
  | Operator of string (** SQL operator spelling. *)
  | End (** Explicit end-of-input marker. *)

(** One token positioned in the original SQL literal. *)
type token =
  { kind : kind (** Token contents after lexical decoding. *)
  ; offset : int (** Zero-based byte offset in the original SQL. *)
  }

(** A parsed cast type: qualified name, array rank, numeric modifiers
    and optional interval field qualifiers. This is syntax, not catalog resolution. *)
type type_name =
  { names : string list (** Qualified native type name, without SQL quoting. *)
  ; dimensions : int (** Number of parsed array suffixes. *)
  ; modifiers : int list
    (** Integer type modifiers in source order, such as precision and scale. *)
  ; interval_fields : string list
    (** Parsed interval field qualifiers, in source order. *)
  }

(** An expression node with its original source offset for inference diagnostics. *)
type expression =
  { node : expression_node (** Expression syntax before source and type resolution. *)
  ; offset : int (** Original source byte offset used for inference errors. *)
  }

(** Expression syntax before type resolution. [Case] stores an optional
    scrutinee, ordered branches and optional ELSE; [Quantified] stores the
    operator, scalar, array and an ANY flag. Boolean flags on null, BETWEEN
    and IN nodes request negation. *)
and expression_node =
  | Column of string list (** Unresolved qualified or unqualified column name. *)
  | Parameter_value of parameter (** Runtime value supplied by an OCaml substitution. *)
  | String_literal of string (** Decoded SQL string constant. *)
  | Number_literal of string (** SQL numeric literal retained as source text. *)
  | Bool_literal of bool (** SQL boolean constant. *)
  | Null_literal (** SQL NULL with a type inferred from its context. *)
  | Default (** SQL DEFAULT, valid only in supported write contexts. *)
  | Unary of string * expression (** Operator and operand. *)
  | Binary of string * expression * expression
  (** Operator, left operand and right operand. *)
  | Cast of expression * type_name
  (** Expression and explicitly requested native SQL type. *)
  | Case of expression option * (expression * expression) list * expression option
  (** Optional scrutinee, ordered WHEN/THEN pairs and optional ELSE. *)
  | Call of call (** Function, aggregate or window call. *)
  | Like_escape of expression * expression
  (** LIKE pattern paired with an explicit escape expression. *)
  | Is_null of expression * bool
  (** Expression and a flag selecting IS NOT NULL when true. *)
  | Between of expression * expression * expression * bool
  (** Value, lower and upper bounds, and a NOT flag. *)
  | In_list of expression * expression list * bool
  (** Value, fixed candidate list and a NOT flag. *)
  | In_query of expression * statement * bool
  (** Value, candidate SELECT and a NOT flag. *)
  | Quantified of string * expression * expression * bool
  (** Operator, scalar, array and a flag selecting ANY over ALL. *)
  | Scalar of statement (** Nested SELECT used as a scalar expression. *)
  | Exists of statement (** Nested SELECT tested for row existence. *)

(** A function or aggregate call. Arguments, aggregate-local ordering,
      FILTER and OVER remain separate for context and scope validation. *)
and call =
  { name : string list (** Qualified function name in resolution order. *)
  ; args : expression list (** Arguments in source order, excluding an aggregate star. *)
  ; star : bool (** True for an aggregate star argument. *)
  ; distinct : bool (** Whether the call applies DISTINCT to its arguments. *)
  ; order : ordering list
    (** Aggregate-local ordering, distinct from statement ordering. *)
  ; filter : expression option (** Optional aggregate FILTER predicate. *)
  ; over : window option (** Optional window specification or named window reference. *)
  }

(** A window specification. [direct] distinguishes a direct named OVER
      reference from a parenthesized specification; [parent] names inherited windows. *)
and window =
  { parent : string option
    (** Inherited or directly referenced window name, when present. *)
  ; partition : expression list (** PARTITION BY expressions in source order. *)
  ; ordering : ordering list (** Window-local ordering keys. *)
  ; frame : frame option (** Explicit frame, absent when PostgreSQL defaults apply. *)
  ; direct : bool (** True for a direct named OVER reference without parentheses. *)
  ; offset : int (** Original source byte offset of the window specification. *)
  }

(** Window frame syntax: mode, inclusive bounds and an optional exclusion.
      Legality and ordering are checked during planning. *)
and frame =
  { mode : string (** Parsed ROWS, RANGE or GROUPS mode. *)
  ; first : frame_bound (** Inclusive lower frame bound. *)
  ; last : frame_bound (** Inclusive upper frame bound. *)
  ; exclusion : string option (** Optional EXCLUDE clause spelling. *)
  }

(** A frame bound. Boolean payloads are true for PRECEDING and false
      for FOLLOWING; bounded offsets remain typed expressions. *)
and frame_bound =
  | Unbounded of bool (** Unbounded PRECEDING when true, FOLLOWING when false. *)
  | Current_row (** The current row or peer group, according to frame mode. *)
  | Bounded of expression * bool (** Offset expression and a PRECEDING flag. *)

(** An expression, ascending-order flag and optional NULLS FIRST flag.
    [None] leaves null ordering to PostgreSQL. *)
and ordering = expression * bool * bool option

(** A selected expression with optional output alias, or a wildcard reference. *)
and projection =
  | Field of expression * string option
  (** Selected expression with an optional output alias. *)
  | All of reference (** Qualified or unqualified wildcard expanded during planning. *)

(** A source occurrence with optional alias and output column aliases.
      The planner checks visibility and resolves names using [offset] for diagnostics. *)
and relation =
  { relation : relation_node (** Source syntax before name and visibility resolution. *)
  ; alias : string option
    (** Explicit source alias, which hides the original relation name. *)
  ; columns : string list (** Explicit output aliases in column order. *)
  ; offset : int (** Original source byte offset of this source occurrence. *)
  }

(** Table, derived/LATERAL query, table functions or a joined source.
      [Functions] carries a WITH ORDINALITY flag; join conditions retain their syntax. *)
and relation_node =
  | Table of reference (** Named table or CTE reference resolved in scope. *)
  | Derived of statement (** Nested SELECT without lateral visibility. *)
  | Lateral of statement (** Nested SELECT with preceding-source visibility. *)
  | Functions of call list * bool (** Table functions and a WITH ORDINALITY flag. *)
  | Join of relation * relation * join_kind * join_condition
  (** Left and right operands, row-preservation kind and join condition. *)

(** Join row-preservation semantics; CROSS joins carry no predicate. *)
and join_kind =
  | Inner (** Keep only matching combinations. *)
  | Left (** Preserve unmatched left rows with null-extended right fields. *)
  | Right (** Preserve unmatched right rows with null-extended left fields. *)
  | Full (** Preserve unmatched rows from both operands. *)
  | Cross (** Cartesian product without a join predicate. *)

(** Explicit ON/USING, NATURAL matching, or an absent join condition. *)
and join_condition =
  | On of expression (** Explicit predicate in the operand source scope. *)
  | Using of reference list (** Column names shared by both join operands. *)
  | Natural (** Match all common column names. *)
  | No_condition (** No predicate, as for a CROSS join. *)

(** A SELECT core before statement-level ordering and pagination.
      Named windows preserve declaration order for resolution. *)
and select =
  { projection : projection list
    (** Selected expressions and wildcards in output order. *)
  ; from : relation option (** Optional FROM source tree. *)
  ; conditions : expression option (** Optional WHERE predicate. *)
  ; group : expression list (** GROUP BY expressions in source order. *)
  ; having : expression option (** Optional HAVING predicate. *)
  ; distinct : bool (** Whether duplicate result rows are eliminated. *)
  ; windows : (string * window) list (** Named window declarations in source order. *)
  }

(** Optional conflict-column target and ON CONFLICT action. *)
and conflict =
  { target : reference list option
    (** Conflict-column references, absent when no explicit target is given. *)
  ; action : conflict_action (** Action for a conflicting row. *)
  }

(** Conflict handling; an update action has ordered assignments and optional WHERE. *)
and conflict_action =
  | Do_nothing (** Skip a conflicting write. *)
  | Do_update of assignment list * expression option
  (** Ordered assignments and optional conflict-update WHERE. *)

(** A target column reference paired with its assigned expression. *)
and assignment = reference * expression

(** Statement body syntax. [Set] stores operator, ALL flag and operands.
      INSERT stores target, alias, columns, optional VALUES, optional SELECT,
      conflict action and RETURNING. UPDATE stores target, alias, assignments,
      FROM, WHERE and RETURNING; DELETE stores target, alias, USING, WHERE
      and RETURNING. These shapes are validated by the planner. *)
and body =
  | Select of select (** One SELECT core. *)
  | Set of string * bool * statement * statement
  (** Set operator, ALL flag and left/right statements. *)
  | Nested of statement
  (** Parenthesized statement with its own ordering/pagination scope. *)
  | Insert of
      reference
      * string option
      * reference list
      * expression list list option
      * statement option
      * conflict option
      * projection list
  (** Target, alias, target columns, optional VALUES, optional SELECT source, conflict action and RETURNING. *)
  | Update of
      reference
      * string option
      * assignment list
      * relation option
      * expression option
      * projection list
  (** Target, alias, assignments, optional FROM, optional WHERE and RETURNING. *)
  | Delete of
      reference * string option * relation option * expression option * projection list
  (** Target, alias, optional USING, optional WHERE and RETURNING. *)

(** A named CTE with optional output names, its body and declaration offset. *)
and cte =
  { name : string (** CTE name visible in its enclosing WITH scope. *)
  ; columns : string list (** Optional declared output-column names in order. *)
  ; query : statement (** The nested statement defining the CTE. *)
  ; offset : int (** Original source byte offset of the CTE declaration. *)
  }

(** One nested statement scope. CTEs, ordering and pagination belong to
      this scope; [offset] points into the original quotation. *)
and statement =
  { ctes : cte list (** WITH definitions in declaration order. *)
  ; recursive : bool (** Whether WITH RECURSIVE was requested. *)
  ; body : body (** Core SELECT, set operation or data-modifying statement. *)
  ; order : ordering list (** Final result-ordering keys. *)
  ; limit : expression option (** Optional LIMIT expression. *)
  ; pagination_offset : expression option
    (** Optional OFFSET expression, distinct from the source byte offset. *)
  ; offset : int (** Original source byte offset of the statement. *)
  }

(** Tokenize SQL without interpreting substitutions inside strings or comments. *)
val lex : string -> (token list, error) Result.t

(** Parse nested SQL; all offsets refer to the original source literal. *)
val parse : token list -> (statement, error) Result.t
