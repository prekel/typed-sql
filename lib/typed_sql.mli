open! Base

(** Build typed SELECT, INSERT, UPDATE and DELETE statements without holding a
    connection. Static [Statement.t] values compile their semantic AST once;
    dynamic statements build and compile one AST for each input. All OCaml
    values are encoded as SQL bind values. *)

(** Validated names for schemas, tables, and columns. *)
module Identifier : sig
  (** A validated, unquoted SQL identifier. Renderers are responsible for
      dialect-specific quoting. *)
  type t

  (** A reason why a string cannot be used as an identifier. *)
  type error =
    [ `Empty (** The identifier contains no characters. *)
    | `Contains_nul
      (** The identifier contains a NUL byte, which SQL quoting cannot preserve
          safely. *)
    ]

  (** Validate an unquoted identifier. Quotes and other ordinary characters
      are accepted and escaped later by the renderer. *)
  val of_string : string -> (t, error) Result.t

  (** Validate an unquoted identifier, raising [Invalid_argument] on failure. *)
  val of_string_exn : string -> t

  (** Return the original unquoted identifier. *)
  val to_string : t -> string

  (** Compare identifiers by their original value. *)
  val equal : t -> t -> bool

  (** Format the original unquoted identifier. *)
  val pp : Formatter.t -> t -> unit

  (** Explain why identifier validation failed. *)
  val error_to_string : error -> string
end

(** Calendar dates without a time of day or time zone. *)
module Date : sig
  type t

  (** Construct a valid proleptic Gregorian date. *)
  val of_ymd : year:int -> month:int -> day:int -> t option

  (** Construct a date or raise [Invalid_argument] when its components are not
      a valid calendar date. *)
  val of_ymd_exn : year:int -> month:int -> day:int -> t

  (** Return [(year, month, day)]. *)
  val to_ymd : t -> int * int * int

  (** Parse the exact ISO 8601 form [YYYY-MM-DD]. *)
  val of_string : string -> t option

  (** Format the exact ISO 8601 form [YYYY-MM-DD]. *)
  val to_string : t -> string

  (** Convert an instant to its UTC calendar date. *)
  val of_ptime : Ptime.t -> t

  (** Convert a date to midnight UTC. *)
  val to_ptime : t -> Ptime.t

  (** Compare two calendar dates. *)
  val equal : t -> t -> bool
end

(** Universally unique identifiers in canonical hexadecimal form. *)
module Uuid : sig
  type t

  (** Parse a UUID written as 8-4-4-4-12 hexadecimal digits. Uppercase digits
      are accepted and normalized to lowercase. *)
  val of_string : string -> t option

  (** Parse a UUID or raise [Invalid_argument] when the input is malformed. *)
  val of_string_exn : string -> t

  (** Return the lowercase canonical representation. *)
  val to_string : t -> string

  (** Compare two UUID values. *)
  val equal : t -> t -> bool
end

(** Exact PostgreSQL [numeric] value. Finite values are compared by value,
    without preserving input scale; [NaN] compares equal to [NaN]. *)
module Decimal : sig
  type t

  (** Parse finite decimal or exponent notation, [NaN], or signed [Infinity].
      Return [None] for malformed input, an overflowing exponent, or a finite
      value too large to format as an OCaml string. *)
  val of_string : string -> t option

  (** Return a normalized decimal without exponent notation, or the canonical
      spelling of a special value. *)
  val to_string : t -> string

  (** Compare exact values, including equal special values. *)
  val equal : t -> t -> bool
end

(** Database representations and application-level codecs. *)
module Db_type : sig
  (** A database representation for an OCaml value. It is independent from any
      execution backend. *)
  type 'a t

  (** SQL boolean represented as an OCaml [bool]. *)
  val bool : bool t

  (** SQL integer represented as an OCaml [int]. *)
  val int : int t

  (** SQL integer represented as an OCaml [int64]. *)
  val int64 : int64 t

  (** SQL floating-point value represented as an OCaml [float]. *)
  val float : float t

  (** Exact PostgreSQL [numeric]. Expressions using this type are rejected by
      SQLite compilation. *)
  val numeric : Decimal.t t

  (** Evidence that a portable scalar type supports SQL [MIN] and [MAX].
      The witness must match the expression's OCaml value type. *)
  module Orderable : sig
    type 'a t

    (** Ordered SQL integer represented as [int]. *)
    val int : int t

    (** Ordered SQL integer represented as [int64]. *)
    val int64 : int64 t

    (** Ordered SQL floating-point value. *)
    val float : float t

    (** Ordered SQL text. *)
    val text : string t

    (** Ordered SQL date. *)
    val date : Date.t t

    (** SQLite orders stored timestamp text. For chronological extrema, values
        written outside the adapter must use a consistent UTC representation. *)
    val timestamp : Ptime.t t

    (** Ordered SQL UUID. *)
    val uuid : Uuid.t t
  end

  (** SQL text represented as an OCaml [string]. *)
  val text : string t

  (** SQL binary data represented as mutable OCaml [bytes]. *)
  val bytes : bytes t

  (** SQL date represented without a time of day or time zone. *)
  val date : Date.t t

  (** SQL timestamp with time zone represented as a UTC [Ptime.t]. *)
  val timestamp : Ptime.t t

  (** SQL UUID represented as a validated [Uuid.t]. *)
  val uuid : Uuid.t t

  (** Make a database representation nullable. *)
  val option : 'a t -> 'a option t

  (** Define a domain type through an existing database representation.
      [encode] runs for parameters and [decode] runs for result fields. Their
      error strings are passed to execution adapters. Each call creates a
      distinct codec identity, even when [name] and [repr] are equal. *)
  val map
    :  ?name:string
    -> encode:('b -> ('a, string) Result.t)
    -> decode:('a -> ('b, string) Result.t)
    -> 'a t
    -> 'b t

  (** Return a diagnostic name. It does not establish codec identity. *)
  val name : 'a t -> string
end

(** Dialect-neutral metadata used by schema introspection and code generation. *)
module Schema_ir : sig
  (** Portable column representations known to the generator. [Unsupported]
      preserves a database type name so introspection never guesses a codec. *)
  type db_type =
    | Bool
    | Int
    | Int64
    | Float
    | Numeric
    | Text
    | Bytes
    | Date
    | Timestamp
    | Uuid
    | Unsupported of string

  type column
  type foreign_key
  type unique_constraint
  type table
  type t

  (** Construct a schema from tables in dependency-independent declaration
      order. *)
  val v : table list -> t

  (** Describe one column, including metadata that affects generated
      descriptors and migrations. Default expressions remain opaque metadata
      and are never inserted into query SQL. *)
  val column
    :  name:Identifier.t
    -> db_type:db_type
    -> nullable:bool
    -> ?default:string
    -> ?generated:bool
    -> ?primary_key_position:int
    -> unit
    -> column

  (** Describe a possibly composite foreign key. Column lists use declaration
      order on both sides. *)
  val foreign_key
    :  columns:Identifier.t list
    -> ?referenced_schema:Identifier.t
    -> referenced_table:Identifier.t
    -> referenced_columns:Identifier.t list
    -> unit
    -> foreign_key

  (** Describe a possibly named unique column set. *)
  val unique_constraint : ?name:Identifier.t -> Identifier.t list -> unique_constraint

  (** Describe one table and its relational constraints. *)
  val table
    :  ?schema:Identifier.t
    -> name:Identifier.t
    -> columns:column list
    -> ?foreign_keys:foreign_key list
    -> ?unique_constraints:unique_constraint list
    -> unit
    -> table

  (** Return tables in introspection or declaration order. *)
  val tables : t -> table list

  (** Return the unqualified table name. *)
  val table_name : table -> Identifier.t

  (** Return the schema qualifier when the database supplied one. *)
  val table_schema : table -> Identifier.t option

  (** Return columns in ordinal order. *)
  val columns : table -> column list

  (** Return declared foreign keys. *)
  val foreign_keys : table -> foreign_key list

  (** Return primary-key-independent unique constraints. *)
  val unique_constraints : table -> unique_constraint list

  (** Return the SQL column name. *)
  val column_name : column -> Identifier.t

  (** Return the portable or preserved unsupported database type. *)
  val column_db_type : column -> db_type

  (** Report whether reads use an option codec. *)
  val column_nullable : column -> bool

  (** Return the database default expression as opaque metadata. *)
  val column_default : column -> string option

  (** Report whether the database generates the column. *)
  val column_generated : column -> bool

  (** Return the one-based position inside a composite primary key. *)
  val column_primary_key_position : column -> int option

  (** Return referencing columns in key order. *)
  val foreign_key_columns : foreign_key -> Identifier.t list

  (** Return the referenced schema qualifier when the database supplied one. *)
  val foreign_key_referenced_schema : foreign_key -> Identifier.t option

  (** Return the unqualified referenced table. *)
  val foreign_key_referenced_table : foreign_key -> Identifier.t

  (** Return referenced columns in key order. *)
  val foreign_key_referenced_columns : foreign_key -> Identifier.t list

  (** Return the database constraint name when available. *)
  val unique_constraint_name : unique_constraint -> Identifier.t option

  (** Return unique columns in key order. *)
  val unique_constraint_columns : unique_constraint -> Identifier.t list
end

(** Persist schema metadata for offline descriptor generation. *)
module Schema_snapshot : sig
  (** A malformed document or unsupported snapshot version. *)
  type error

  (** Encode version 1 JSON with a fixed field order, indentation and a final
      newline. All schema list orders and opaque default/type strings are
      preserved. Optional metadata is written as JSON [null]. No database or
      filesystem access is performed. *)
  val to_string : Schema_ir.t -> string

  (** Decode one JSON document. All fields are required; duplicate and unknown
      fields, invalid identifiers, incorrect JSON types and unsupported versions
      are rejected. This validates the snapshot structure, not database
      constraints or whether the generator supports its SQL types. *)
  val of_string : string -> (Schema_ir.t, error) Result.t

  (** Explain the error with a JSON field path, or [$] for a syntax error. *)
  val error_to_string : error -> string
end

(** Generate table, column, accessor and projection descriptors as OCaml source. *)
module Schema_codegen : sig
  type error =
    | Empty_table of Identifier.t
    | Unsupported_type of
        { table : Identifier.t
        ; column : Identifier.t
        ; database_type : string
        }

  (** Explain why descriptor source could not be generated. *)
  val error_to_string : error -> string

  (** Generate modules in schema order. Names are normalized to valid OCaml
      identifiers; SQL names remain unchanged in quoted string literals.
      Normalized names that collide with another generated binding or a
      generator-owned binding receive deterministic [_2], [_3], ... suffixes
      in schema order. The returned source opens [Base] and [Typed_sql] and can
      be compiled directly as a module with [ppx_let]. Each table module
      retains column defaults, generated and primary-key flags, foreign keys,
      and unique constraints as ordinary metadata values. *)
  val generate : Schema_ir.t -> (string, error) Result.t
end

(** Typed table descriptors. *)
module Table : sig
  (** A table descriptor. The phantom row type distinguishes schemas at compile
      time and is normally declared abstract inside a generated table module. *)
  type 'row t

  (** Construct a table descriptor from validated identifiers. *)
  val v : ?schema:Identifier.t -> Identifier.t -> 'row t

  (** Construct a table descriptor from strings, raising [Invalid_argument]
      when the table or schema name is invalid. *)
  val v_exn : ?schema:string -> string -> 'row t

  (** Return the unqualified table name. *)
  val name : 'row t -> Identifier.t

  (** Return the optional schema qualifier. *)
  val schema : 'row t -> Identifier.t Option.t
end

(** Typed column descriptors owned by a table. *)
module Column : sig
  (** A column tied to a table's phantom row type. ['base] is the non-null SQL
      value type and ['value] is the value read from a regular table reference. *)
  type ('row, 'base, 'value) t

  (** Construct a non-nullable column descriptor. *)
  val v : 'row Table.t -> Identifier.t -> 'a Db_type.t -> ('row, 'a, 'a) t

  (** Construct a non-nullable column descriptor from a string, raising
      [Invalid_argument] when the name is invalid. *)
  val v_exn : 'row Table.t -> string -> 'a Db_type.t -> ('row, 'a, 'a) t

  (** Construct a nullable column. Its base database type remains ['a], while
      reads and assignments use ['a option]. *)
  val nullable_v : 'row Table.t -> Identifier.t -> 'a Db_type.t -> ('row, 'a, 'a option) t

  (** Construct a nullable column from a string, raising [Invalid_argument]
      when the name is invalid. *)
  val nullable_v_exn : 'row Table.t -> string -> 'a Db_type.t -> ('row, 'a, 'a option) t

  (** Return the table descriptor that owns the column. *)
  val table : ('row, 'base, 'value) t -> 'row Table.t

  (** Return the unquoted column name. *)
  val name : ('row, 'base, 'value) t -> Identifier.t

  (** Return the non-null database representation, excluding schema
      nullability. *)
  val base_db_type : ('row, 'base, 'value) t -> 'base Db_type.t

  (** Return the representation observed through a regular table reference,
      including schema nullability. *)
  val db_type : ('row, 'base, 'value) t -> 'value Db_type.t
end

(** Query-local references to regular table occurrences. *)
module Table_ref : sig
  (** An occurrence of a table in one query. Values are created by
      [Query.from], [Query.from_values], or a join callback; an escaped
      reference from another query is rejected by the compiler. *)
  type 'row t
end

(** Query-local references to null-extended outer-join occurrences. *)
module Nullable_table_ref : sig
  (** A table occurrence made nullable by an outer join. *)
  type 'row t
end

(** A SELECT known to return exactly one typed SQL expression. Scalar queries
    are embedded with [Expr.scalar_subquery] or membership predicates; execute a
    top-level value through [Result_query] instead. *)
module Scalar_query : sig
  type ('a, +'requirements) t
end

(** A validated runtime parameter for [LIMIT] or [OFFSET]. *)
module Pagination_parameter : sig
  type +'requirements t
end

(** SQL predicates and boolean composition. *)
module Condition : sig
  (** A predicate using SQL three-valued logic. *)
  type +'requirements t

  (** A predicate that always evaluates to SQL [TRUE]. Normalization removes it
      when it is an identity element. *)
  val true_ : 'requirements t

  (** A predicate that always evaluates to SQL [FALSE]. Normalization folds
      surrounding boolean expressions when possible. *)
  val false_ : 'requirements t

  (** Negate a predicate using SQL [NOT]. *)
  val not_ : 'requirements t -> 'requirements t

  (** Infix composition for SQL predicates. *)
  module Infix : sig
    (** SQL conjunction. *)
    val ( &&. ) : 'requirements t -> 'requirements t -> 'requirements t

    (** SQL disjunction. *)
    val ( ||. ) : 'requirements t -> 'requirements t -> 'requirements t
  end
end

(** Typed scalar SQL expressions and comparisons. *)
module Expr : sig
  (** A typed scalar SQL expression. *)
  type ('a, +'requirements) t

  (** Refer to a column from a regular table occurrence. The phantom row type
      prevents using a column declared for another table descriptor. *)
  val column
    :  'row Table_ref.t
    -> ('row, 'base, 'value) Column.t
    -> ('value, 'requirements) t

  (** A column selected through the nullable side of a LEFT JOIN. Existing
      schema nullability is flattened, so the result contains one [option]. *)
  val nullable_column
    :  'row Nullable_table_ref.t
    -> ('row, 'base, 'value) Column.t
    -> ('base option, 'requirements) t

  (** Treat an expression as nullable without changing its SQL. This is useful
      for null checks on a non-nullable expression. *)
  val to_nullable : ('a, 'requirements) t -> ('a option, 'requirements) t

  (** Capture an OCaml constant in the current semantic AST. A static statement
      captures it at definition time; a dynamic statement captures it during
      the current callback invocation. It is sent as a bind value and never
      interpolated into rendered SQL. Runtime input in a static statement must
      be introduced through [Statement.parameters]. *)
  val constant : 'a Db_type.t -> 'a -> ('a, 'requirements) t

  (** Use [default] when the nullable expression evaluates to SQL [NULL].
      This includes a scalar subquery that returned no row. The result uses
      [default]'s database type and decoder; SQL [COALESCE] does not distinguish
      an absent scalar row from a row containing [NULL]. *)
  val coalesce
    :  ('a option, 'requirements) t
    -> default:('a, 'requirements) t
    -> ('a, 'requirements) t

  (** Test a nullable expression with SQL [IS NULL]. *)
  val is_null : ('a option, 'requirements) t -> 'requirements Condition.t

  (** Test a nullable expression with SQL [IS NOT NULL]. *)
  val is_not_null : ('a option, 'requirements) t -> 'requirements Condition.t

  (** Test whether an expression equals one of the OCaml constants captured in
      the current AST. The constants are encoded as bind values. An empty list
      is normalized to SQL [FALSE]. *)
  val in_ : ('a, 'requirements) t -> 'a list -> 'requirements Condition.t

  (** Test whether an expression differs from every OCaml constant captured in
      the current AST. The constants are encoded as bind values. An empty list
      is normalized to SQL [TRUE]. As in SQL, a [NULL] in a non-empty list can
      make the predicate unknown. *)
  val not_in : ('a, 'requirements) t -> 'a list -> 'requirements Condition.t

  (** Test membership against typed SQL expressions instead of OCaml values. *)
  val in_exprs
    :  ('a, 'requirements) t
    -> ('a, 'requirements) t list
    -> 'requirements Condition.t

  (** Test non-membership against typed SQL expressions. *)
  val not_in_exprs
    :  ('a, 'requirements) t
    -> ('a, 'requirements) t list
    -> 'requirements Condition.t

  (** Test whether an expression lies inside an inclusive range whose OCaml
      bounds are captured in the current AST and encoded as bind values. *)
  val between : ('a, 'requirements) t -> lower:'a -> upper:'a -> 'requirements Condition.t

  (** Test an inclusive range using SQL expressions as both bounds. *)
  val between_exprs
    :  ('a, 'requirements) t
    -> lower:('a, 'requirements) t
    -> upper:('a, 'requirements) t
    -> 'requirements Condition.t

  (** Compare values with null-safe SQL semantics. PostgreSQL uses [IS DISTINCT
      FROM], while SQLite uses its equivalent [IS NOT] operator. *)
  val is_distinct_from
    :  ('a, 'requirements) t
    -> ('a, 'requirements) t
    -> 'requirements Condition.t

  (** Null-safe comparison with an OCaml constant captured in the current AST. *)
  val is_distinct_from_value : ('a, 'requirements) t -> 'a -> 'requirements Condition.t

  (** Build a searched SQL [CASE]. Conditions are tested in list order. An
      empty branch list yields [else_] directly at execution. All branch
      expressions have the same OCaml and database type. *)
  val case
    :  ('requirements Condition.t * ('a, 'requirements) t) list
    -> else_:('a, 'requirements) t
    -> ('a, 'requirements) t

  (** Convert text to lowercase using the database's portable scalar
      function. *)
  val lower : (string, 'requirements) t -> (string, 'requirements) t

  (** Convert text to uppercase. *)
  val upper : (string, 'requirements) t -> (string, 'requirements) t

  (** Return the number of characters in text. Lowering uses [CHAR_LENGTH] on
      PostgreSQL and [LENGTH] on SQLite. *)
  val length : (string, 'requirements) t -> (int, 'requirements) t

  (** Concatenate two text expressions with SQL [||]. *)
  val concat
    :  (string, 'requirements) t
    -> (string, 'requirements) t
    -> (string, 'requirements) t

  (** Concatenate text with an OCaml string captured in the current AST. *)
  val concat_value : (string, 'requirements) t -> string -> (string, 'requirements) t

  (** Count rows in the current aggregate group. *)
  val count_all : (int64, 'requirements) t

  (** Count non-null values of an expression. *)
  val count : ('a, 'requirements) t -> (int64, 'requirements) t

  (** Count distinct non-null values of an expression. *)
  val count_distinct : ('a, 'requirements) t -> (int64, 'requirements) t

  (** Sum non-null [int] values into [int64]. An empty group, or one containing
      only nulls, returns [None]. *)
  val sum_int : (int, 'r) t -> (int64 option, 'r) t

  (** As [sum_int], accepting nullable input. *)
  val sum_int_nullable : (int option, 'r) t -> (int64 option, 'r) t

  (** Sum non-null [float] values. Empty or entirely null groups return [None]. *)
  val sum_float : (float, 'r) t -> (float option, 'r) t

  (** As [sum_float], accepting nullable input. *)
  val sum_float_nullable : (float option, 'r) t -> (float option, 'r) t

  (** Minimum non-null value of an ordered scalar type. An empty group returns
      [None]. The witness determines which types this operation supports. *)
  val min : 'a Db_type.Orderable.t -> ('a, 'r) t -> ('a option, 'r) t

  (** Maximum non-null value, with the same empty-group behavior as [min]. *)
  val max : 'a Db_type.Orderable.t -> ('a, 'r) t -> ('a option, 'r) t

  (** As [min], accepting nullable input without nesting options. *)
  val min_nullable : 'a Db_type.Orderable.t -> ('a option, 'r) t -> ('a option, 'r) t

  (** As [max], accepting nullable input without nesting options. *)
  val max_nullable : 'a Db_type.Orderable.t -> ('a option, 'r) t -> ('a option, 'r) t

  (** Embed a one-column SELECT, returning [None] when it returns no row.
      Compilation requires [LIMIT 0/1] or an aggregate belonging to this SELECT
      without [GROUP BY]. No limit is added implicitly. For an already nullable
      expression prefer [scalar_subquery_nullable] to avoid nested options. *)
  val scalar_subquery : ('a, 'requirements) Scalar_query.t -> ('a option, 'requirements) t

  (** Embed a nullable one-column SELECT without adding another option layer.
      An absent row and a row containing SQL [NULL] both decode as [None].
      The cardinality requirements are the same as [scalar_subquery]. *)
  val scalar_subquery_nullable
    :  ('a option, 'requirements) Scalar_query.t
    -> ('a option, 'requirements) t

  (** The transaction's current timestamp. Both supported dialects render the
      standard SQL [CURRENT_TIMESTAMP] expression. *)
  val current_timestamp : (Ptime.t, 'requirements) t

  (** Type-safe arithmetic over SQL integers represented as OCaml [int]. *)
  module Int : sig
    module Infix : sig
      val ( +. ) : (int, 'r) t -> (int, 'r) t -> (int, 'r) t
      val ( -. ) : (int, 'r) t -> (int, 'r) t -> (int, 'r) t
      val ( *. ) : (int, 'r) t -> (int, 'r) t -> (int, 'r) t
      val ( /. ) : (int, 'r) t -> (int, 'r) t -> (int, 'r) t
    end
  end

  (** Type-safe arithmetic over SQL integers represented as OCaml [int64]. *)
  module Int64 : sig
    module Infix : sig
      val ( +. ) : (int64, 'r) t -> (int64, 'r) t -> (int64, 'r) t
      val ( -. ) : (int64, 'r) t -> (int64, 'r) t -> (int64, 'r) t
      val ( *. ) : (int64, 'r) t -> (int64, 'r) t -> (int64, 'r) t
      val ( /. ) : (int64, 'r) t -> (int64, 'r) t -> (int64, 'r) t
    end
  end

  (** Type-safe arithmetic over SQL floating-point values. *)
  module Float : sig
    module Infix : sig
      val ( +. ) : (float, 'r) t -> (float, 'r) t -> (float, 'r) t
      val ( -. ) : (float, 'r) t -> (float, 'r) t -> (float, 'r) t
      val ( *. ) : (float, 'r) t -> (float, 'r) t -> (float, 'r) t
      val ( /. ) : (float, 'r) t -> (float, 'r) t -> (float, 'r) t
    end
  end

  (** Operators are the primary API for constructing comparisons. Operators with
      a dot compare expressions; operators ending with [$] capture a
      current-AST OCaml constant using the type carried by the left expression.
      Constants are encoded as SQL bind values. *)
  module Infix : sig
    (** SQL equality between two expressions. *)
    val ( =. ) : ('a, 'r) t -> ('a, 'r) t -> 'r Condition.t

    (** SQL inequality between two expressions. *)
    val ( <>. ) : ('a, 'r) t -> ('a, 'r) t -> 'r Condition.t

    (** SQL less-than comparison between two expressions. *)
    val ( <. ) : ('a, 'r) t -> ('a, 'r) t -> 'r Condition.t

    (** SQL less-than-or-equal comparison between two expressions. *)
    val ( <=. ) : ('a, 'r) t -> ('a, 'r) t -> 'r Condition.t

    (** SQL greater-than comparison between two expressions. *)
    val ( >. ) : ('a, 'r) t -> ('a, 'r) t -> 'r Condition.t

    (** SQL greater-than-or-equal comparison between two expressions. *)
    val ( >=. ) : ('a, 'r) t -> ('a, 'r) t -> 'r Condition.t

    (** SQL equality with an OCaml constant captured in the current AST. *)
    val ( =$ ) : ('a, 'r) t -> 'a -> 'r Condition.t

    (** SQL inequality with an OCaml constant captured in the current AST. *)
    val ( <>$ ) : ('a, 'r) t -> 'a -> 'r Condition.t

    (** SQL less-than comparison with an OCaml constant captured in the current AST. *)
    val ( <$ ) : ('a, 'r) t -> 'a -> 'r Condition.t

    (** SQL less-than-or-equal comparison with a current-AST OCaml constant. *)
    val ( <=$ ) : ('a, 'r) t -> 'a -> 'r Condition.t

    (** SQL greater-than comparison with an OCaml constant captured in the current AST. *)
    val ( >$ ) : ('a, 'r) t -> 'a -> 'r Condition.t

    (** SQL greater-than-or-equal comparison with a current-AST OCaml constant. *)
    val ( >=$ ) : ('a, 'r) t -> 'a -> 'r Condition.t

    (** SQL [LIKE] between text expressions. *)
    val ( =~. ) : (string, 'r) t -> (string, 'r) t -> 'r Condition.t

    (** SQL [LIKE] with an OCaml pattern captured in the current AST. Wildcards
        are interpreted by the database and are not escaped by typed-sql. *)
    val ( =~$ ) : (string, 'r) t -> string -> 'r Condition.t
  end
end

(** All expression-comparison and condition-composition operators. Opening this
    module is the recommended way to use operators while building queries. *)
module Infix : sig
  (** Comparison operators inherited from [Expr.Infix]. *)
  include module type of Expr.Infix

  (** Boolean operators inherited from [Condition.Infix]. *)
  include module type of Condition.Infix
end

(** Ordering keys local to a collection aggregate. *)
module Aggregate_order : sig
  (** One typed aggregate-local ordering key. *)
  type +'requirements t

  (** Sort collection elements by an expression in ascending order. *)
  val asc : ('a, 'requirements) Expr.t -> 'requirements t

  (** Sort collection elements by an expression in descending order. *)
  val desc : ('a, 'requirements) Expr.t -> 'requirements t
end

(** Applicative result projections. *)
module Projection : sig
  (** An applicative description of SELECT expressions and their result
      decoder. A standalone [return] projection is rejected because SQL SELECT must
      contain at least one expression. *)
  type ('a, +'requirements) t

  (** Standard applicative operations. [return] contributes no SQL expression;
      [map] changes only decoding; [both], [map2], [map3], [apply], and [all]
      concatenate selected expressions from left to right. *)
  include Base.Applicative.S2 with type ('a, 'requirements) t := ('a, 'requirements) t

  (** Add one typed SQL expression and decode its field unchanged. *)
  val expr : ('a, 'requirements) Expr.t -> ('a, 'requirements) t

  (** Select two expressions from left to right and decode them as a pair. *)
  val pair
    :  ('a, 'requirements) Expr.t
    -> ('b, 'requirements) Expr.t
    -> ('a * 'b, 'requirements) t

  (** Aggregate the projected fields over the current SQL group and decode
      them as a list. [order_by] is aggregate-local and therefore determines
      list order; without it the order is unspecified. [filter] excludes rows
      before aggregation, which is useful for nullable sides of outer joins.

      Rows are represented internally as positional JSON arrays, but JSON is
      not part of the public result type. Empty groups decode as the empty
      list. Binary fields are rejected during compilation. *)
  val multiset_agg
    :  ?filter:'requirements Condition.t
    -> ?order_by:'requirements Aggregate_order.t list
    -> ('a, 'requirements) t
    -> ('a list, 'requirements) t

  (** Syntax support for applicative [let%map] and parallel [and] bindings. *)
  module Let_syntax : sig
    val return : 'a -> ('a, 'requirements) t

    include
      Base.Applicative.Applicative_infix2
      with type ('a, 'requirements) t := ('a, 'requirements) t

    module Let_syntax : sig
      val return : 'a -> ('a, 'requirements) t
      val map : ('a, 'requirements) t -> f:('a -> 'b) -> ('b, 'requirements) t

      val both
        :  ('a, 'requirements) t
        -> ('b, 'requirements) t
        -> ('a * 'b, 'requirements) t

      module Open_on_rhs : sig end
    end
  end
end

(** A nonempty aggregate projection. Its constructors add an aggregate SQL
    expression; the compiler separately checks that referenced sources belong
    to the query and that the aggregate is local. *)
module Aggregate_projection : sig
  type ('a, +'requirements) t

  (** Change only the decoded OCaml result; retain the SQL aggregates. *)
  val map : ('a, 'r) t -> f:('a -> 'b) -> ('b, 'r) t

  (** Combine aggregate expressions from left to right. *)
  val both : ('a, 'r) t -> ('b, 'r) t -> ('a * 'b, 'r) t

  (** Recommended syntax for combining aggregates with [let%map] and [and].
      There is no [return]: a value without an aggregate would break the
      guarantee that this projection contains an aggregate. *)
  module Let_syntax : sig
    module Let_syntax : sig
      (** The operations used by [ppx_let]; they have the semantics of [map]
          and [both] above. *)
      val map : ('a, 'r) t -> f:('a -> 'b) -> ('b, 'r) t

      val both : ('a, 'r) t -> ('b, 'r) t -> ('a * 'b, 'r) t

      module Open_on_rhs : sig end
    end
  end

  (** Count all rows, including rows with null fields. *)
  val count_all : (int64, 'r) t

  (** Count non-null values of an expression. *)
  val count : ('a, 'r) Expr.t -> (int64, 'r) t

  (** Count distinct non-null values of an expression. *)
  val count_distinct : ('a, 'r) Expr.t -> (int64, 'r) t

  (** Sum [int] values into [int64]; empty or entirely null groups yield [None]. *)
  val sum_int : (int, 'r) Expr.t -> (int64 option, 'r) t

  (** As [sum_int], accepting nullable input. *)
  val sum_int_nullable : (int option, 'r) Expr.t -> (int64 option, 'r) t

  (** Sum [float] values; empty or entirely null groups yield [None]. *)
  val sum_float : (float, 'r) Expr.t -> (float option, 'r) t

  (** As [sum_float], accepting nullable input. *)
  val sum_float_nullable : (float option, 'r) Expr.t -> (float option, 'r) t

  (** Minimum of an ordered scalar type; an empty group yields [None]. *)
  val min : 'a Db_type.Orderable.t -> ('a, 'r) Expr.t -> ('a option, 'r) t

  (** Maximum of an ordered scalar type; an empty group yields [None]. *)
  val max : 'a Db_type.Orderable.t -> ('a, 'r) Expr.t -> ('a option, 'r) t

  (** As [min], accepting nullable input without nesting options. *)
  val min_nullable : 'a Db_type.Orderable.t -> ('a option, 'r) Expr.t -> ('a option, 'r) t

  (** As [max], accepting nullable input without nesting options. *)
  val max_nullable : 'a Db_type.Orderable.t -> ('a option, 'r) Expr.t -> ('a option, 'r) t

  (** Collect projected rows from the current group. [filter] excludes rows;
      [order_by] determines list order. Without ordering, list order is
      unspecified. Empty groups decode as empty lists. Unsupported field types
      are rejected during compilation. *)
  val multiset_agg
    :  ?filter:'r Condition.t
    -> ?order_by:'r Aggregate_order.t list
    -> ('a, 'r) Projection.t
    -> ('a list, 'r) t
end

(** Phantom proofs about SELECT result cardinality. These types describe what
    the DSL and compiler can prove before execution; adapters still enforce
    the requested runtime cardinality as a defensive check. *)
module Cardinality : sig
  (** No useful upper bound is known. This does not mean that the SELECT must
      return multiple rows. *)
  type many = [ `Many ]

  (** The SELECT can return zero or one row. [Query.limit_one] establishes this
      proof. *)
  type at_most_one = [ `At_most_one ]

  (** The SELECT is guaranteed to return one row. An [exactly_one] result is
      also accepted by APIs requiring [at_most_one]. *)
  type exactly_one =
    [ `At_most_one
    | `Exactly_one
    ]
end

(** Finished statements that decode returned rows. *)
module Result_query : sig
  (** Marker for a completed SELECT. *)
  type select

  (** Marker for a completed INSERT, UPDATE, or DELETE with [RETURNING]. *)
  type returning

  (** A deferred statement that returns decoded rows. ['cardinality] records a
      proof about the number of rows it can return; ['kind] distinguishes a
      SELECT from DML [RETURNING]. *)
  type ('result, 'kind, +'cardinality, +'requirements) t
end

(** Finished statements that return only an affected-row result. *)
module Command : sig
  (** A deferred INSERT, UPDATE, or DELETE statement without returned rows. *)
  type +'requirements t
end

(** A named, typed relation backed by a SELECT. The [table] and [columns]
    descriptors define the relation exposed to its enclosing query; the
    compiler verifies that they match the SELECT output. *)
module Derived_table : sig
  type ('row, +'requirements) t

  (** A structural description of fields exposed by an inferred relation.
      Unlike [Projection.t], this type has no [map]: every field remains a SQL
      expression that can be referenced by an enclosing query. *)
  module Fields : sig
    type ('fields, 'nullable_fields, 'requirements) t

    (** Expose one expression as a relation field. Its SQL name is assigned
        deterministically. *)
    val expr
      :  ('value, 'requirements) Expr.t
      -> ( ('value, 'requirements) Expr.t
           , ('value option, 'requirements) Expr.t
           , 'requirements )
           t

    (** Combine two structural field descriptions, preserving their shape. *)
    val both
      :  ('left, 'nullable_left, 'requirements) t
      -> ('right, 'nullable_right, 'requirements) t
      -> ('left * 'right, 'nullable_left * 'nullable_right, 'requirements) t

    (** Expose two expressions as a pair of relation fields. *)
    val pair
      :  ('left, 'requirements) Expr.t
      -> ('right, 'requirements) Expr.t
      -> ( ('left, 'requirements) Expr.t * ('right, 'requirements) Expr.t
           , ('left option, 'requirements) Expr.t * ('right option, 'requirements) Expr.t
           , 'requirements )
           t
  end

  (** A derived relation whose visible field accessors were inferred from the
      expressions passed to [Query.select_relation]. *)
  type ('fields, 'nullable_fields, 'requirements) inferred

  (** Give a SELECT result a relation descriptor so it can be used as a FROM
      source or JOIN target. [columns] must project direct columns from [table]
      in the relation's declared order. The inner result's cardinality proof
      is not exposed by the relation; a SELECT started from it has
      [Cardinality.many]. *)
  val create
    :  table:'row Table.t
    -> columns:('row Table_ref.t -> ('columns, 'requirements) Projection.t)
    -> ('result, Result_query.select, 'cardinality, 'requirements) Result_query.t
    -> ('row, 'requirements) t
end

(** Typed SQL [VALUES] rows used as a [FROM] or join source. The [Table.t] and
    column descriptors name the virtual relation; they do not cause a read from
    a database table. Literal cell values remain bind parameters. *)
module Values : sig
  type ('row, +'requirements) t

  (** Structurally typed rows. Every row in [create] has the same field shape;
      the compiler also checks the ordered database types, including
      nullability and mapped codec identity, against the declared columns. *)
  module Row : sig
    type ('fields, 'nullable_fields, 'requirements) t =
      ('fields, 'nullable_fields, 'requirements) Derived_table.Fields.t

    (** Make a one-field row. *)
    val expr
      :  ('value, 'requirements) Expr.t
      -> ( ('value, 'requirements) Expr.t
           , ('value option, 'requirements) Expr.t
           , 'requirements )
           t

    (** Concatenate row shapes, preserving their nested OCaml pair. *)
    val both
      :  ('left, 'nullable_left, 'requirements) t
      -> ('right, 'nullable_right, 'requirements) t
      -> ('left * 'right, 'nullable_left * 'nullable_right, 'requirements) t

    (** Make a two-field row. *)
    val pair
      :  ('left, 'requirements) Expr.t
      -> ('right, 'requirements) Expr.t
      -> ( ('left, 'requirements) Expr.t * ('right, 'requirements) Expr.t
           , ('left option, 'requirements) Expr.t * ('right option, 'requirements) Expr.t
           , 'requirements )
           t
  end

  (** A dynamically shaped row cell. Its type is checked against the declared
      column descriptors during compilation. *)
  module Cell : sig
    type +'requirements t

    (** Package one typed expression for a dynamic row; compilation checks its
        database type against the corresponding relation column. *)
    val expr : ('value, 'requirements) Expr.t -> 'requirements t
  end

  (** Create named columns and rows whose OCaml field structure is checked at
      construction sites. Rows must match the declared columns in width and
      database types when compiled. [columns] must describe distinct direct
      columns of [table]. The [first] argument ensures the relation has a row.
      Cell expressions may contain independent scalar subqueries; references
      to enclosing sources and aggregates are rejected. *)
  val create
    :  table:'row Table.t
    -> columns:('row Table_ref.t -> ('columns, 'requirements) Projection.t)
    -> first:('fields, 'nullable_fields, 'requirements) Row.t
    -> rest:('fields, 'nullable_fields, 'requirements) Row.t list
    -> ('row, 'requirements) t

  (** Create rows from dynamically shaped cell lists. The compiler checks that
      each row has the declared number and database types of fields. An empty
      row list is a compilation error. Cells may contain independent
      expressions and scalar subqueries; references to enclosing sources and
      aggregates are rejected. *)
  val create_dynamic
    :  table:'row Table.t
    -> columns:('row Table_ref.t -> ('columns, 'requirements) Projection.t)
    -> rows:'requirements Cell.t list list
    -> ('row, 'requirements) t
end

(** Common table expressions. A definition has a typed handle which is valid
    only in the callback passed to [with_result] or [with_command]. *)
module Cte : sig
  (** A relation made available by a CTE definition. *)
  type 'row t

  (** A CTE definition and the handle through which it can be referenced. *)
  type ('handle, +'requirements) definition

  (** PostgreSQL and SQLite materialization hints for a non-recursive SELECT
      CTE. SQLite requires version 3.35 or later. *)
  type materialization =
    [ `Materialized
    | `Not_materialized
    ]

  (** Choose duplicate-eliminating or duplicate-preserving recursion. *)
  type recursion =
    [ `Union
    | `Union_all
    ]

  (** Define a non-recursive CTE from a typed relation. A CTE handle describes
      its columns, not the number of rows produced by its definition. *)
  val select
    :  ?materialization:materialization
    -> ('row, 'requirements) Derived_table.t
    -> ('row t, 'requirements) definition

  (** Define one recursive CTE. [anchor] cannot reference the new CTE;
      [step] receives its sole typed self-reference. *)
  val recursive
    :  union:recursion
    -> anchor:('row, 'requirements) Derived_table.t
    -> step:('row t -> ('row, 'requirements) Derived_table.t)
    -> ('row t, 'requirements) definition

  (** Attach a CTE to a SELECT or a DML statement with [RETURNING]. The
      callback receives the CTE handle in lexical scope. The result cardinality
      proof is preserved. *)
  val with_result
    :  ('handle, 'requirements) definition
    -> f:('handle -> ('result, 'kind, 'cardinality, 'requirements) Result_query.t)
    -> ('result, 'kind, 'cardinality, 'requirements) Result_query.t

  (** Attach a CTE to an INSERT, UPDATE, or DELETE command. *)
  val with_command
    :  ('handle, 'requirements) definition
    -> f:('handle -> 'requirements Command.t)
    -> 'requirements Command.t
end

(** Immutable SELECT builders. *)
module Query : sig
  (** Marker for a SELECT without [GROUP BY]. *)
  type ungrouped

  (** Marker for a SELECT with at least one [GROUP BY] expression. *)
  type grouped

  (** An immutable SELECT builder. ['ctx] is the callback context of visible
      table references; ['grouping] tracks whether [GROUP BY] is present;
      ['cardinality] is the current row-bound proof. *)
  type ('ctx, 'grouping, +'cardinality, +'requirements) t

  (** SELECT builder for one ungrouped aggregate row. It supports sources,
      joins, and filters, but has no grouping, [HAVING], or pagination. Finish
      it with [aggregate_one]; the compiler still checks source locality. *)
  module Aggregate : sig
    type ('ctx, +'requirements) t

    (** Start with a table. *)
    val from : 'row Table.t -> ('row Table_ref.t, 'r) t

    (** Start with a named derived table. *)
    val from_derived : ('row, 'r) Derived_table.t -> ('row Table_ref.t, 'r) t

    (** Start with an inferred derived relation. *)
    val from_relation
      :  ('fields, 'nullable_fields, 'r) Derived_table.inferred
      -> ('fields, 'r) t

    (** Start with a typed [VALUES] relation. *)
    val from_values : ('row, 'r) Values.t -> ('row Table_ref.t, 'r) t

    (** Start with a CTE visible in the current lexical scope. *)
    val from_cte : 'row Cte.t -> ('row Table_ref.t, 'r) t

    (** Add an inner join to a table; [on] sees both the old and new sources. *)
    val inner_join
      :  'row Table.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Table_ref.t, 'r) t

    (** Add a left join; fields of the new source are nullable. *)
    val left_join
      :  'row Table.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Nullable_table_ref.t, 'r) t

    (** Inner join a named derived table. *)
    val inner_join_derived
      :  ('row, 'r) Derived_table.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Table_ref.t, 'r) t

    (** Left join a named derived table. *)
    val left_join_derived
      :  ('row, 'r) Derived_table.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Nullable_table_ref.t, 'r) t

    (** Inner join an inferred relation. *)
    val inner_join_relation
      :  ('fields, 'nullable_fields, 'r) Derived_table.inferred
      -> on:('ctx -> 'fields -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'fields, 'r) t

    (** Left join an inferred relation; its fields become nullable. *)
    val left_join_relation
      :  ('fields, 'nullable_fields, 'r) Derived_table.inferred
      -> on:('ctx -> 'fields -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'nullable_fields, 'r) t

    (** Join a typed [VALUES] relation. *)
    val inner_join_values
      :  ('row, 'r) Values.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Table_ref.t, 'r) t

    (** Left join a typed [VALUES] relation; its fields become nullable. *)
    val left_join_values
      :  ('row, 'r) Values.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Nullable_table_ref.t, 'r) t

    (** Inner join a CTE in scope. *)
    val inner_join_cte
      :  'row Cte.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Table_ref.t, 'r) t

    (** Left join a CTE in scope. *)
    val left_join_cte
      :  'row Cte.t
      -> on:('ctx -> 'row Table_ref.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx * 'row Nullable_table_ref.t, 'r) t

    (** Filter input rows before aggregation. *)
    val where : ('ctx -> 'r Condition.t) -> ('ctx, 'r) t -> ('ctx, 'r) t

    (** Add a filter only when the option has a value. *)
    val where_opt
      :  'a option
      -> f:('ctx -> 'a -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx, 'r) t

    (** Keep SQL shape stable for an optional bind parameter: absent values
        disable the predicate without rebuilding the statement. *)
    val where_optional_param
      :  ('a option, 'r) Expr.t
      -> f:('ctx -> ('a option, 'r) Expr.t -> 'r Condition.t)
      -> ('ctx, 'r) t
      -> ('ctx, 'r) t
  end

  (** Direction for one [ORDER BY] key. *)
  type direction =
    [ `Asc (** Ascending SQL order. *)
    | `Desc (** Descending SQL order. *)
    ]

  (** Start a SELECT builder from one table. Subsequent callbacks receive the
      only valid reference to this occurrence. A new source has cardinality
      [Cardinality.many]. *)
  val from
    :  'row Table.t
    -> ('row Table_ref.t, ungrouped, Cardinality.many, 'requirements) t

  (** Start a SELECT builder from a typed derived relation. The new outer
      SELECT starts with [Cardinality.many] independently of the inner query. *)
  val from_derived
    :  ('row, 'requirements) Derived_table.t
    -> ('row Table_ref.t, ungrouped, Cardinality.many, 'requirements) t

  (** Start a SELECT from a relation built by [select_relation]. The context
      has the same structural shape as its [Derived_table.Fields] value. The
      new outer SELECT starts with [Cardinality.many]. *)
  val from_relation
    :  ('fields, 'nullable_fields, 'requirements) Derived_table.inferred
    -> ('fields, ungrouped, Cardinality.many, 'requirements) t

  (** Start a SELECT from a typed [VALUES] relation. *)
  val from_values
    :  ('row, 'requirements) Values.t
    -> ('row Table_ref.t, ungrouped, Cardinality.many, 'requirements) t

  (** Start a SELECT builder from a CTE handle in lexical scope. The new outer
      SELECT starts with [Cardinality.many]. *)
  val from_cte
    :  'row Cte.t
    -> ('row Table_ref.t, ungrouped, Cardinality.many, 'requirements) t

  (** Finish the builder with a result projection. Keeping [select] last avoids
      a temporary projection while filters and joins are assembled. The
      builder's cardinality proof is preserved in the [Result_query]. *)
  val select
    :  ('ctx -> ('result, 'requirements) Projection.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('result, Result_query.select, 'cardinality, 'requirements) Result_query.t

  (** Collect every row of a finished SELECT into one projected list. The
      nested SELECT may be correlated with sources visible where this value is
      constructed, and retains its filters, grouping, set operations,
      ordering and pagination. Empty results decode as the empty list.

      As with SQL multisets, element order is not a semantic guarantee even
      when the nested query has [ORDER BY]. Use [Projection.multiset_agg] with
      aggregate-local [order_by] when list order is part of the contract. *)
  val multiset
    :  ('result, Result_query.select, 'cardinality, 'requirements) Result_query.t
    -> ('result list, 'requirements) Projection.t

  (** Finish an ungrouped aggregate SELECT and establish cardinality
      [Cardinality.exactly_one]. The compiler requires at least one local
      aggregate and rejects [HAVING],
      [OFFSET], a parameterized [LIMIT], and a literal [LIMIT] below one.
      Use regular [select] when the query does not satisfy this contract. *)
  val select_exactly_one
    :  ('ctx -> ('result, 'requirements) Projection.t)
    -> ('ctx, ungrouped, 'cardinality, 'requirements) t
    -> ( 'result
         , Result_query.select
         , Cardinality.exactly_one
         , 'requirements )
         Result_query.t

  (** Select one scalar expression without [FROM]. PostgreSQL and SQLite
      produce exactly one row; the compiler checks any references captured by
      the expression and rejects unavailable sources. A nullable expression
      may still decode as [None]. *)
  val select_one
    :  ('a, 'requirements) Expr.t
    -> ('a, Result_query.select, Cardinality.exactly_one, 'requirements) Result_query.t

  (** Finish an ungrouped aggregate builder with an [exactly_one] result type.
      [Aggregate_projection] ensures an aggregate expression is present; the
      compiler verifies source locality and rejects invalid SQL. *)
  val aggregate_one
    :  ('ctx -> ('result, 'requirements) Aggregate_projection.t)
    -> ('ctx, 'requirements) Aggregate.t
    -> ( 'result
         , Result_query.select
         , Cardinality.exactly_one
         , 'requirements )
         Result_query.t

  (** Finish the builder as a reusable derived relation. Only structural
      [Derived_table.Fields] values are accepted, so arbitrary decoding through
      [Projection.map] cannot be exposed as SQL fields. The builder's
      cardinality proof is intentionally absent from the resulting relation;
      an outer SELECT starts with [Cardinality.many]. *)
  val select_relation
    :  ('ctx -> ('fields, 'nullable_fields, 'requirements) Derived_table.Fields.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('fields, 'nullable_fields, 'requirements) Derived_table.inferred

  (** Finish a builder as a one-expression query suitable for a scalar
      subquery or [IN] predicate. When embedded with [Expr.scalar], the
      compiler checks the query's SQL shape for an at-most-one-row guarantee;
      that check is independent of the public cardinality phantom. *)
  val select_scalar
    :  ('ctx -> ('value, 'requirements) Expr.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('value, 'requirements) Scalar_query.t

  (** Test whether an unfinished SELECT returns at least one row. Its
      projection is intentionally omitted and rendered as [SELECT 1]. The
      query may capture references from the enclosing callback. *)
  val exists
    :  ('inner_ctx, 'grouping, 'cardinality, 'requirements) t
    -> 'requirements Condition.t

  (** Test whether an unfinished SELECT returns at least one row and use the
      result as a non-null boolean expression in a projection. An empty result
      gives [false]. The SELECT projection is intentionally omitted and
      rendered as [SELECT 1]. The query may capture references from the
      enclosing callback; invalid source references fail compilation. *)
  val exists_expr
    :  ('inner_ctx, 'grouping, 'cardinality, 'requirements) t
    -> (bool, 'requirements) Expr.t

  (** Negated [EXISTS]. *)
  val not_exists
    :  ('inner_ctx, 'grouping, 'cardinality, 'requirements) t
    -> 'requirements Condition.t

  (** Test membership in a typed one-column SELECT. *)
  val in_subquery
    :  ('a, 'requirements) Expr.t
    -> ('a, 'requirements) Scalar_query.t
    -> 'requirements Condition.t

  (** Test non-membership in a typed one-column SELECT. *)
  val not_in_subquery
    :  ('a, 'requirements) Expr.t
    -> ('a, 'requirements) Scalar_query.t
    -> 'requirements Condition.t

  (** Append an [INNER JOIN]. The [on] callback sees the existing context and a
      regular reference to the newly joined table. Any existing cardinality
      bound is preserved because [LIMIT] applies after joins. *)
  val inner_join
    :  'row Table.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** [on] sees the new table before null extension. Subsequent callbacks
      receive a nullable reference and must use [Expr.nullable_column]. Any
      existing cardinality bound is preserved. *)
  val left_join
    :  'row Table.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Nullable_table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** Join a typed derived relation while preserving the current cardinality
      bound. *)
  val inner_join_derived
    :  ('row, 'requirements) Derived_table.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** Left join a typed derived relation. The appended reference is nullable;
      the current cardinality bound is preserved. *)
  val left_join_derived
    :  ('row, 'requirements) Derived_table.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Nullable_table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** Join a relation built by [select_relation]. The appended context has the
      structural shape declared by its fields. The current cardinality bound
      is preserved. *)
  val inner_join_relation
    :  ('fields, 'nullable_fields, 'requirements) Derived_table.inferred
    -> on:('ctx -> 'fields -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'fields, 'grouping, 'cardinality, 'requirements) t

  (** Left join a relation built by [select_relation]. Its exposed expressions
      are nullable after the join. The current cardinality bound is preserved. *)
  val left_join_relation
    :  ('fields, 'nullable_fields, 'requirements) Derived_table.inferred
    -> on:('ctx -> 'fields -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'nullable_fields, 'grouping, 'cardinality, 'requirements) t

  (** Join a typed [VALUES] relation while preserving the current cardinality
      bound. *)
  val inner_join_values
    :  ('row, 'requirements) Values.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** Left join a typed [VALUES] relation; the appended reference is nullable. *)
  val left_join_values
    :  ('row, 'requirements) Values.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Nullable_table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** Join a CTE handle in lexical scope while preserving the current
      cardinality bound. *)
  val inner_join_cte
    :  'row Cte.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** Left join a CTE handle. The appended reference is nullable; the current
      cardinality bound is preserved. *)
  val left_join_cte
    :  'row Cte.t
    -> on:('ctx -> 'row Table_ref.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx * 'row Nullable_table_ref.t, 'grouping, 'cardinality, 'requirements) t

  (** Repeated calls combine predicates with SQL AND. Filtering preserves any
      existing upper bound on result rows. *)
  val where
    :  ('ctx -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t

  (** Add a predicate only when the optional value is [Some]. [None] returns
      the same immutable query unchanged. The cardinality bound is preserved. *)
  val where_opt
    :  'value option
    -> f:('ctx -> 'value -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t

  (** Add a fixed-shape optional predicate controlled by a nullable expression.
      The rendered condition is [(parameter IS NULL OR predicate)]. This is
      useful for nullable runtime parameters in static statements: unlike
      [where_opt], it does not change the SQL shape. The predicate receives the
      same nullable expression so it can be compared with nullable columns or
      expressions. The cardinality bound is preserved. *)
  val where_optional_param
    :  ('value option, 'requirements) Expr.t
    -> f:('ctx -> ('value option, 'requirements) Expr.t -> 'requirements Condition.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t

  (** Remove duplicate result rows with portable SQL [DISTINCT]. The
      cardinality bound is preserved. *)
  val distinct
    :  ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t

  (** Append one [GROUP BY] expression. Repeated calls preserve call order and
      any existing cardinality bound. *)
  val group_by
    :  ('ctx -> ('value, 'requirements) Expr.t)
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, grouped, 'cardinality, 'requirements) t

  (** Add an aggregate-group predicate. Repeated calls combine predicates with
      SQL [AND]. The compiler rejects ungrouped non-aggregate expressions. The
      current upper bound is preserved. *)
  val having
    :  ('ctx -> 'requirements Condition.t)
    -> ('ctx, grouped, 'cardinality, 'requirements) t
    -> ('ctx, grouped, 'cardinality, 'requirements) t

  (** Append one ordering key. Repeated calls preserve call order and the
      current cardinality bound. *)
  val order_by
    :  ('ctx -> ('value, 'requirements) Expr.t)
    -> direction
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t

  (** Set the maximum number of returned rows. The compiler rejects negative
      values. A later call replaces the previous limit. Because an arbitrary
      integer may exceed one, this operation resets the proof to
      [Cardinality.many], even when the supplied value happens to be zero or
      one. *)
  val limit
    :  int
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, Cardinality.many, 'requirements) t

  (** Set [LIMIT 1]. This proves that the SELECT returns at most one row. A
      later [limit] or [limit_param] replaces that proof. It does not prove
      that a row exists, so the result is unsuitable for
      [Statement.Portable.query_one]. *)
  val limit_one
    :  ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, Cardinality.at_most_one, 'requirements) t

  (** Set the number of rows to skip. The compiler rejects negative values. A
      later call replaces the previous offset. Skipping rows preserves an
      existing upper bound. *)
  val offset
    :  int
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t

  (** Set [LIMIT] from a runtime statement parameter validated as non-negative
      before execution. Since the value is unknown while the statement is
      built, this resets the cardinality proof to [Cardinality.many]. *)
  val limit_param
    :  'requirements Pagination_parameter.t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, Cardinality.many, 'requirements) t

  (** Set [OFFSET] from a runtime statement parameter validated as
      non-negative before execution. Skipping rows preserves an existing upper
      bound. *)
  val offset_param
    :  'requirements Pagination_parameter.t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t
    -> ('ctx, 'grouping, 'cardinality, 'requirements) t

  (** Combine two SELECT results using portable SQL set operations. The
      compiler verifies that both projected database-type sequences match.
      Every set operation resets cardinality to [Cardinality.many], regardless
      of operand proofs. The combined result uses the left projection's
      decoder. The optional [order_by] orders by selected output fields using
      checked SQL identifiers, such as [Column.name Book.id_column]. Each field
      must occur exactly once in the left projection. *)
  val union
    :  ?order_by:(Identifier.t * direction) list
    -> ('result, Result_query.select, 'left_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, 'right_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, Cardinality.many, 'requirements) Result_query.t

  (** Combine results with duplicate-preserving [UNION ALL]. An optional
      [order_by] orders by selected output fields using checked SQL identifiers. *)
  val union_all
    :  ?order_by:(Identifier.t * direction) list
    -> ('result, Result_query.select, 'left_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, 'right_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, Cardinality.many, 'requirements) Result_query.t

  (** Return distinct rows present in both operands with [INTERSECT]. An
      optional [order_by] orders by selected output fields using checked SQL
      identifiers. *)
  val intersect
    :  ?order_by:(Identifier.t * direction) list
    -> ('result, Result_query.select, 'left_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, 'right_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, Cardinality.many, 'requirements) Result_query.t

  (** Return distinct left rows absent from the right operand with [EXCEPT]. An
      optional [order_by] orders by selected output fields using checked SQL
      identifiers. *)
  val except
    :  ?order_by:(Identifier.t * direction) list
    -> ('result, Result_query.select, 'left_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, 'right_cardinality, 'requirements) Result_query.t
    -> ('result, Result_query.select, Cardinality.many, 'requirements) Result_query.t
end

(** Immutable INSERT builders. *)
module Insert : sig
  (** An INSERT builder. The compiler rejects empty rows, duplicate target
      columns, different column sets across VALUES rows, and mixing VALUES
      assignments with a SELECT source. Values passed to [set] are current-AST
      constants encoded as bind values. *)
  type ('row, +'requirements) t

  (** Non-empty ordered target columns for [from_select]. The order must match
      the SQL projection of the SELECT. All columns belong to the same phantom
      row type; compilation also checks their table descriptor, uniqueness,
      and exact database types, including nullability and mapped codecs. *)
  module Columns : sig
    type 'row t

    (** Start a nonempty ordered target list. *)
    val column : ('row, 'base, 'value) Column.t -> 'row t

    (** Append a target column without changing the preceding order. *)
    val add : ('row, 'base, 'value) Column.t -> 'row t -> 'row t
  end

  (** Non-empty columns identifying a unique key. The database checks that a
      matching unique index or constraint exists. Every column carries the
      same phantom row type as the INSERT target; compilation also verifies
      that its owning table descriptor matches the target table. *)
  module Conflict_target : sig
    type 'row t

    (** Start a conflict target with one column. *)
    val column : ('row, 'base, 'value) Column.t -> 'row t

    (** Append a column to a composite conflict target. Ordering is preserved;
        compilation rejects duplicate columns. *)
    val add : ('row, 'base, 'value) Column.t -> 'row t -> 'row t
  end

  (** An INSERT paired with a conflict target and awaiting an action. *)
  type ('row, +'requirements) conflict

  (** Immutable assignments and an optional predicate for the conflicting row. *)
  module Conflict_update : sig
    (** An update action for one target table. *)
    type ('row, +'requirements) t

    (** Start without assignments or a predicate. Compilation rejects an
        action that still has no assignments after optional fields are omitted. *)
    val empty : ('row, 'requirements) t

    (** Append an OCaml constant assignment captured in the current AST. The
        constant is encoded as a bind value. Duplicate columns and columns
        owned by another table descriptor are rejected. *)
    val set
      :  ('row, 'base, 'value) Column.t
      -> 'value
      -> ('row, 'requirements) t
      -> ('row, 'requirements) t

    (** Append an expression assignment. The [existing] and [excluded]
        references are visible, including inside correlated subqueries.
        Columns owned by another table descriptor and direct aggregate
        expressions are rejected. *)
    val set_expr
      :  ('row, 'base, 'value) Column.t
      -> ('value, 'requirements) Expr.t
      -> ('row, 'requirements) t
      -> ('row, 'requirements) t

    (** Omit [None]; [Some None] assigns SQL NULL to a nullable column. *)
    val set_opt
      :  ('row, 'base, 'value) Column.t
      -> 'value option
      -> ('row, 'requirements) t
      -> ('row, 'requirements) t

    (** Omit [None], or append the supplied typed expression. *)
    val set_expr_opt
      :  ('row, 'base, 'value) Column.t
      -> ('value, 'requirements) Expr.t option
      -> ('row, 'requirements) t
      -> ('row, 'requirements) t

    (** Restrict the conflict update. Repeated calls combine with SQL AND.
        Without a predicate, every conflicting row is updated. FALSE or NULL
        skips the update and produces no RETURNING row. This predicate does
        not filter successful inserts. *)
    val where
      :  'requirements Condition.t
      -> ('row, 'requirements) t
      -> ('row, 'requirements) t
  end

  (** Start an INSERT containing one empty row. *)
  val into : 'row Table.t -> ('row, 'requirements) t

  (** Assign a column from an OCaml constant captured in the current AST. The
      constant is encoded as a bind value. In a static statement, use
      [set_expr] with [Statement.parameters] for runtime input. *)
  val set
    :  ('row, 'base, 'value) Column.t
    -> 'value
    -> ('row, 'requirements) t
    -> ('row, 'requirements) t

  (** Assign a column from a typed expression. VALUES cannot reference the
      target or excluded row; independent scalar subqueries are allowed. *)
  val set_expr
    :  ('row, 'base, 'value) Column.t
    -> ('value, 'requirements) Expr.t
    -> ('row, 'requirements) t
    -> ('row, 'requirements) t

  (** Assign SQL [DEFAULT] to a column without inventing an OCaml value. This
      adds a PostgreSQL requirement because SQLite does not support [DEFAULT]
      inside a [VALUES] row. *)
  val default
    :  ('row, 'base, 'value) Column.t
    -> ('row, ([> `Postgresql ] as 'requirements)) t
    -> ('row, 'requirements) t

  (** Build a multi-row INSERT. Each function receives an empty row builder.
      Rows may call [set], [set_expr], or [default] in any order, but every row
      must assign the same set of columns. *)
  val rows
    :  'row Table.t
    -> (('row, 'requirements) t -> ('row, 'requirements) t) list
    -> ('row, 'requirements) t

  (** Replace the untouched empty VALUES row with a SELECT source. The SELECT
      may contain CTEs or set operations, but cannot refer to the INSERT target
      without introducing it as its own source. Compilation checks target
      ownership, uniqueness, and ordered database types, including nullability
      and mapped codec identity. Mixing this source with [set], [default], or
      [rows] is rejected; conflict actions and [returning] remain available. *)
  val from_select
    :  'row Columns.t
    -> ('result, Result_query.select, 'cardinality, 'requirements) Result_query.t
    -> ('row, 'requirements) t
    -> ('row, 'requirements) t

  (** Ignore rows rejected by a unique or exclusion conflict. PostgreSQL and
      SQLite both render [ON CONFLICT DO NOTHING]; other integrity errors still
      fail through the execution adapter. *)
  val on_conflict_do_nothing : ('row, 'requirements) t -> ('row, 'requirements) t

  (** Select a non-empty conflict target. The result must be completed with
      [do_nothing] or [do_update] before it can be finalized. *)
  val on_conflict
    :  'row Conflict_target.t
    -> ('row, 'requirements) t
    -> ('row, 'requirements) conflict

  (** Ignore a conflict matching the selected target. *)
  val do_nothing : ('row, 'requirements) conflict -> ('row, 'requirements) t

  (** Update the conflicting row. The callback receives the proposed
      [excluded] row and current [existing] row. Compilation rejects an empty
      or duplicate assignment list and references outside these two rows.
      The [excluded] reference is scoped to this action and cannot appear in
      VALUES or RETURNING. PostgreSQL rejects a multi-row
      UPSERT that updates the same conflicting row twice. *)
  val do_update
    :  (existing:'row Table_ref.t
        -> excluded:'row Table_ref.t
        -> ('row, 'requirements) Conflict_update.t)
    -> ('row, 'requirements) conflict
    -> ('row, 'requirements) t

  (** Finish an INSERT without returned rows. Compilation rejects an empty or
      duplicate assignment list. *)
  val command : ('row, 'requirements) t -> 'requirements Command.t

  (** Finish an INSERT with a typed [RETURNING] projection. DML does not carry
      a row-count proof, so the result cardinality is [Cardinality.many]. Use
      [Statement.Portable.expect_one] or
      [Statement.Portable.expect_optional] when an application invariant
      expects fewer rows. *)
  val returning
    :  ('row Table_ref.t -> ('result, 'requirements) Projection.t)
    -> ('row, 'requirements) t
    -> ('result, Result_query.returning, Cardinality.many, 'requirements) Result_query.t
end

(** Immutable UPDATE builders with type-level row-scope authorization. *)
module Update : sig
  (** Marker for an UPDATE that cannot yet be finalized. *)
  type unscoped

  (** Marker for an UPDATE authorized by [where] or [all_rows]. *)
  type scoped

  (** Only builders scoped by [where] or [all_rows] can be finalized. *)
  type ('row, 'scope, +'requirements) t

  (** Start an UPDATE without assignments or row scope. *)
  val table : 'row Table.t -> ('row, unscoped, 'requirements) t

  (** Assign a column from an OCaml constant captured in the current AST. The
      constant is encoded as a bind value. In a static statement, use
      [set_expr] with [Statement.parameters] for runtime input. *)
  val set
    :  ('row, 'base, 'value) Column.t
    -> 'value
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'scope, 'requirements) t

  (** Assign a column from a typed expression. The compiler rejects an
      expression referring to another query source. *)
  val set_expr
    :  ('row, 'base, 'value) Column.t
    -> ('value, 'requirements) Expr.t
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'scope, 'requirements) t

  (** Assign SQL [DEFAULT] to a column. This adds a PostgreSQL requirement
      because SQLite does not support [UPDATE SET DEFAULT]. *)
  val default
    :  ('row, 'base, 'value) Column.t
    -> ('row, 'scope, ([> `Postgresql ] as 'requirements)) t
    -> ('row, 'scope, 'requirements) t

  (** Conditionally assign an OCaml constant captured in the current AST.
      [None] leaves the builder unchanged. For a nullable column, [Some None]
      writes SQL [NULL]. *)
  val set_opt
    :  ('row, 'base, 'value) Column.t
    -> 'value option
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'scope, 'requirements) t

  (** Conditionally assign an expression. [None] leaves the builder unchanged. *)
  val set_expr_opt
    :  ('row, 'base, 'value) Column.t
    -> ('value, 'requirements) Expr.t option
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'scope, 'requirements) t

  (** Add one table to [UPDATE ... FROM] and configure the update while its
      reference is in lexical scope. The callback receives the target, the new
      source, and the current immutable builder. Repeated calls append sources. *)
  val from
    :  'source Table.t
    -> f:
         ('row Table_ref.t
          -> 'source Table_ref.t
          -> ('row, 'scope, 'requirements) t
          -> ('row, 'new_scope, 'requirements) t)
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'new_scope, 'requirements) t

  (** Add a typed derived relation to [UPDATE ... FROM]. *)
  val from_derived
    :  ('source, 'requirements) Derived_table.t
    -> f:
         ('row Table_ref.t
          -> 'source Table_ref.t
          -> ('row, 'scope, 'requirements) t
          -> ('row, 'new_scope, 'requirements) t)
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'new_scope, 'requirements) t

  (** Add a relation built by [Query.select_relation] to [UPDATE ... FROM]. *)
  val from_relation
    :  ('fields, 'nullable_fields, 'requirements) Derived_table.inferred
    -> f:
         ('row Table_ref.t
          -> 'fields
          -> ('row, 'scope, 'requirements) t
          -> ('row, 'new_scope, 'requirements) t)
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'new_scope, 'requirements) t

  (** Add a CTE handle in lexical scope to [UPDATE ... FROM]. *)
  val from_cte
    :  'source Cte.t
    -> f:
         ('row Table_ref.t
          -> 'source Table_ref.t
          -> ('row, 'scope, 'requirements) t
          -> ('row, 'new_scope, 'requirements) t)
    -> ('row, 'scope, 'requirements) t
    -> ('row, 'new_scope, 'requirements) t

  (** Add a row predicate and mark the UPDATE as scoped. Repeated calls combine
      predicates with SQL [AND]. *)
  val where
    :  ('row Table_ref.t -> 'requirements Condition.t)
    -> ('row, 'scope, 'requirements) t
    -> ('row, scoped, 'requirements) t

  (** Explicitly authorize updating every row, removing any previous filter. *)
  val all_rows : ('row, 'scope, 'requirements) t -> ('row, scoped, 'requirements) t

  (** Finish a scoped UPDATE without returned rows. Compilation rejects an
      empty or duplicate assignment list. *)
  val command : ('row, scoped, 'requirements) t -> 'requirements Command.t

  (** Finish a scoped UPDATE with a typed [RETURNING] projection. The result
      cardinality is [Cardinality.many], even when the predicate is expected to
      identify a unique row. *)
  val returning
    :  ('row Table_ref.t -> ('result, 'requirements) Projection.t)
    -> ('row, scoped, 'requirements) t
    -> ('result, Result_query.returning, Cardinality.many, 'requirements) Result_query.t
end

(** Immutable DELETE builders with type-level row-scope authorization. *)
module Delete : sig
  (** Marker for a DELETE that cannot yet be finalized. *)
  type unscoped

  (** Marker for a DELETE authorized by [where] or [all_rows]. *)
  type scoped

  (** Only builders scoped by [where] or [all_rows] can be finalized. *)
  type ('row, 'scope, +'requirements) t

  (** Start a DELETE without row scope. *)
  val from : 'row Table.t -> ('row, unscoped, 'requirements) t

  (** Add a row predicate and mark the DELETE as scoped. Repeated calls combine
      predicates with SQL [AND]. *)
  val where
    :  ('row Table_ref.t -> 'requirements Condition.t)
    -> ('row, 'scope, 'requirements) t
    -> ('row, scoped, 'requirements) t

  (** Explicitly authorize deleting every row, removing any previous filter. *)
  val all_rows : ('row, 'scope, 'requirements) t -> ('row, scoped, 'requirements) t

  (** Finish a scoped DELETE without returned rows. *)
  val command : ('row, scoped, 'requirements) t -> 'requirements Command.t

  (** Finish a scoped DELETE with a typed [RETURNING] projection. The result
      cardinality is [Cardinality.many]. *)
  val returning
    :  ('row Table_ref.t -> ('result, 'requirements) Projection.t)
    -> ('row, scoped, 'requirements) t
    -> ('result, Result_query.returning, Cardinality.many, 'requirements) Result_query.t
end

(** Supported SQL dialects. *)
module Dialect : sig
  (** SQL rendering rules selected during pure compilation. *)
  type t =
    | Postgresql (** PostgreSQL quoting and [$n] placeholders. *)
    | Sqlite (** SQLite quoting and [?n] placeholders. *)

  (** No dialect-specific requirement. *)
  type portable = []

  (** A statement requiring PostgreSQL semantics. *)
  type postgresql = [ `Postgresql ]

  (** A statement requiring SQLite semantics. *)
  type sqlite = [ `Sqlite ]

  (** A typed choice of compilation dialect. *)
  type 'requirements witness

  val postgresql : postgresql witness
  val sqlite : sqlite witness
  val kind : _ witness -> t

  (** Return the stable lowercase dialect name used in diagnostics. *)
  val to_string : t -> string
end

(** PostgreSQL-specific builders. Using one adds a PostgreSQL requirement to
    the resulting statement. *)
module Postgresql : sig
  (** PostgreSQL aggregate expressions whose result is exact [numeric]. Each
      constructor marks its query as PostgreSQL-only. [SUM], [MIN], and [MAX]
      return [None] for empty or entirely null groups. *)
  module Numeric : sig
    (** Sum [bigint] values without [int64] overflow in the result. *)
    val sum_int64
      :  (int64, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t

    (** As [sum_int64], accepting nullable input. *)
    val sum_int64_nullable
      :  (int64 option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t

    (** Sum exact [numeric] values. *)
    val sum_numeric
      :  (Decimal.t, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t

    (** As [sum_numeric], accepting nullable input. *)
    val sum_numeric_nullable
      :  (Decimal.t option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t

    (** Minimum non-null [numeric] value. *)
    val min_numeric
      :  (Decimal.t, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t

    (** Maximum non-null [numeric] value. *)
    val max_numeric
      :  (Decimal.t, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t

    (** As [min_numeric], accepting nullable input. *)
    val min_numeric_nullable
      :  (Decimal.t option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t

    (** As [max_numeric], accepting nullable input. *)
    val max_numeric_nullable
      :  (Decimal.t option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Expr.t
  end

  (** [Numeric] aggregates packaged for [Query.aggregate_one]. These retain
      the PostgreSQL requirement and can be combined with
      [Aggregate_projection.Let_syntax]. *)
  module Numeric_projection : sig
    (** Sum [bigint] values into an exact [numeric] result. *)
    val sum_int64
      :  (int64, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t

    (** As [sum_int64], accepting nullable input. *)
    val sum_int64_nullable
      :  (int64 option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t

    (** Sum exact [numeric] values. *)
    val sum_numeric
      :  (Decimal.t, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t

    (** As [sum_numeric], accepting nullable input. *)
    val sum_numeric_nullable
      :  (Decimal.t option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t

    (** Minimum non-null [numeric] value. *)
    val min_numeric
      :  (Decimal.t, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t

    (** Maximum non-null [numeric] value. *)
    val max_numeric
      :  (Decimal.t, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t

    (** As [min_numeric], accepting nullable input. *)
    val min_numeric_nullable
      :  (Decimal.t option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t

    (** As [max_numeric], accepting nullable input. *)
    val max_numeric_nullable
      :  (Decimal.t option, ([> `Postgresql ] as 'r)) Expr.t
      -> (Decimal.t option, 'r) Aggregate_projection.t
  end

  module Query : sig
    (** Add [HAVING] before [GROUP BY]. PostgreSQL treats the input as one
        aggregate group; portable [Query.having] requires [Query.grouped]. The
        existing cardinality bound is preserved, but
        [Query.select_exactly_one] rejects ungrouped [HAVING] because it can
        remove the aggregate row. *)
    val having
      :  ('ctx -> 'requirements Condition.t)
      -> ( 'ctx
           , Query.ungrouped
           , 'cardinality
           , ([> `Postgresql ] as 'requirements) )
           Query.t
      -> ('ctx, Query.ungrouped, 'cardinality, 'requirements) Query.t

    (** PostgreSQL's duplicate-preserving [INTERSECT ALL]. It resets result
        cardinality to [Cardinality.many]. The optional [order_by] orders the
        rows by selected output fields using checked SQL identifiers. *)
    val intersect_all
      :  ?order_by:(Identifier.t * [ `Asc | `Desc ]) list
      -> ( 'result
           , Result_query.select
           , 'left_cardinality
           , ([> `Postgresql ] as 'requirements) )
           Result_query.t
      -> ('result, Result_query.select, 'right_cardinality, 'requirements) Result_query.t
      -> ('result, Result_query.select, Cardinality.many, 'requirements) Result_query.t

    (** Return duplicate-preserving left rows absent from the right operand
        with [EXCEPT ALL]. The optional [order_by] orders the combined rows by
        selected output fields using checked SQL identifiers. *)
    val except_all
      :  ?order_by:(Identifier.t * [ `Asc | `Desc ]) list
      -> ( 'result
           , Result_query.select
           , 'left_cardinality
           , ([> `Postgresql ] as 'requirements) )
           Result_query.t
      -> ('result, Result_query.select, 'right_cardinality, 'requirements) Result_query.t
      -> ('result, Result_query.select, Cardinality.many, 'requirements) Result_query.t
  end

  module Cte : sig
    (** Define a data-modifying CTE with [RETURNING]. The CTE relation is
        described by [table] and [columns], and may be used by the enclosing
        PostgreSQL statement. The input result's cardinality is irrelevant to
        the CTE relation and is not exposed by [Cte.t]. *)
    val returning
      :  table:'row Table.t
      -> columns:
           ('row Table_ref.t
            -> ('columns, ([> `Postgresql ] as 'requirements)) Projection.t)
      -> ('result, Result_query.returning, 'cardinality, 'requirements) Result_query.t
      -> ('row Cte.t, 'requirements) Cte.definition

    (** Define a data-modifying CTE used only for its effect. *)
    val command
      :  ([> `Postgresql ] as 'requirements) Command.t
      -> (unit, 'requirements) Cte.definition
  end
end

(** Errors returned by pure compilation. *)
module Compile_error : sig
  (** A structural error found after query normalization and before SQL is
      exposed to an adapter. *)
  type t =
    | Empty_projection
    (** SELECT or RETURNING has no SQL expression. Applicative constants alone
          do not form a valid projection. *)
    | Empty_values_columns (** A [VALUES] relation declares no output columns. *)
    | Empty_values_rows (** A [VALUES] relation contains no rows. *)
    | Foreign_source of
        { visible : int list (** Source identities available at the invalid expression. *)
        ; actual : int (** The source identity used by the invalid expression. *)
        }
    (** An expression uses a table occurrence outside its query scope.
          [visible] and [actual] are diagnostic source identities. *)
    | Negative_limit of int (** [Query.limit] received a negative value. *)
    | Negative_offset of int (** [Query.offset] received a negative value. *)
    | Empty_assignments of [ `Insert | `Update ]
    (** INSERT or UPDATE was finalized without assigning a column. *)
    | Empty_insert_row of int
    (** A one-based row in a multi-row INSERT has no assignments. *)
    | Duplicate_assignment of Identifier.t
    (** The same target column was assigned more than once. *)
    | Mismatched_insert_columns of
        { row : int (** One-based index of the mismatched row. *)
        ; expected : Identifier.t list (** Columns established by the first row. *)
        ; actual : Identifier.t list (** Columns assigned by this row. *)
        }
    (** A multi-row INSERT contains different column sets. Ordering may differ
        and is normalized to the first row during rendering. *)
    | Missing_insert_source
    (** A malformed internal INSERT has neither VALUES rows nor a SELECT. *)
    | Mixed_insert_sources
    (** An INSERT builder combined VALUES assignments and a SELECT source. *)
    | Mismatched_insert_select_projection of
        { expected : string list
        ; actual : string list
        }
    (** Target columns and SELECT projection have different ordered database
        type fingerprints, including nullability and mapped codec identity. *)
    | Empty_conflict_target
    (** A malformed private AST contains an empty [ON CONFLICT] target. Public
        [Insert.Conflict_target] values are non-empty by construction. *)
    | Duplicate_conflict_target of Identifier.t
    (** The same column occurs more than once in a conflict target. *)
    | Invalid_conflict_target_source of
        { expected : int
        ; actual : int
        } (** A conflict target column belongs to another table source. *)
    | Empty_conflict_update (** [ON CONFLICT DO UPDATE] contains no assignments. *)
    | Invalid_assignment_source of
        { expected : int (** The source identity of the command target. *)
        ; actual : int (** The source identity stored in the malformed assignment. *)
        }
    (** A malformed internal assignment targets a different table occurrence.
          Public builders preserve this invariant by construction. *)
    | Unsupported_operation of
        { operation : string (** Stable operation name used in diagnostics. *)
        ; dialect : Dialect.t (** Dialect selected for compilation. *)
        }
    (** The AST requests semantics unavailable in the selected dialect. The
        compiler reports this during lowering and does not render substitute
        SQL. *)
    | Aggregate_not_allowed of string
    (** An aggregate appears in a clause that does not allow it. The string
        names the rejected SQL clause. *)
    | Nested_aggregate (** One aggregate expression is used inside another aggregate. *)
    | Ungrouped_expression
    (** An aggregate query selects, orders, or filters by a non-aggregate
        expression whose columns are absent from [GROUP BY]. *)
    | Scalar_subquery_may_return_many_rows
    (** Scalar embedding requires an explicit [LIMIT 0/1] or an aggregate of
        the current SELECT without [GROUP BY]. Membership and existence
        subqueries are not subject to this restriction. *)
    | Exactly_one_query_not_proven
    (** [Query.select_exactly_one] requires an ungrouped aggregate without
        [HAVING], [OFFSET], a parameterized [LIMIT], or a literal [LIMIT]
        below one. *)
    | Invalid_relation_column of int
    (** A relation output descriptor is not a direct column. The integer is
        its one-based position. *)
    | Duplicate_relation_column of Identifier.t
    (** A relation exposes one column name more than once. *)
    | Mismatched_relation_projection of
        { expected : string list
        ; actual : string list
        }
    (** Relation descriptor and query output have different database-type
        sequences. *)
    | Mismatched_set_projection of
        { expected : string list
        ; actual : string list
        }
    (** The two operands of a set operation have different database-type
        sequences. *)
    | Invalid_set_order_field of
        { field : string
        ; matches : int
        }
    (** A final set-operation ordering field does not identify exactly one
        output field. *)
    | Mismatched_values_row_arity of
        { row : int
        ; expected : int
        ; actual : int
        } (** A one-based row has a different field count from the relation. *)
    | Mismatched_values_row_types of
        { row : int
        ; expected : string list
        ; actual : string list
        }
    (** A one-based row has database types different from the declared
               columns, in projection order. *)
    | Unknown_cte of int (** A source refers to a CTE outside its lexical scope. *)
    | Invalid_recursive_reference of int
    (** The recursive term must use its own CTE exactly once as a top-level
        source. *)
    | Unsupported_multiset_field_type of
        { path : int list (** One-based field positions through nested collections. *)
        ; type_name : string (** Unsupported database representation. *)
        }
    (** A collection contains a field which cannot be represented by the
        portable JSON transport. *)

  (** Format a compilation error for a user. *)
  val pp : Formatter.t -> t -> unit

  (** Return a human-readable compilation error. *)
  val to_string : t -> string
end

(** Backend-independent affected-row results. *)
module Affected_rows : sig
  (** [Unknown] means that the backend cannot report the count, not that zero
      rows were affected. *)
  type t = Typed_sql_private.Affected_rows.t =
    | Known of int (** The backend reported an exact number of changed rows. *)
    | Unknown (** The backend completed the command but cannot report an exact count. *)

  (** Format an affected-row result. *)
  val pp : Formatter.t -> t -> unit
end

(** A reusable query or command accepting one typed input. Static constructors
    compile at definition time and use [parameters] for runtime values.
    [Dynamic.Portable] builds and compiles from input on each execution. *)
module Statement : sig
  (** A reusable statement from ['input] to ['output]. ['requirements]
      constrains the dialects that may compile or execute it. Query output
      shape includes the chosen execution cardinality; command output is
      [Affected_rows.t]. *)
  type ('input, 'output, +'requirements) t =
    ('input, 'output, 'requirements) Typed_sql_private.Statement.t

  (** A static statement definition that failed compilation for one dialect. *)
  type definition_error =
    { dialect : Dialect.t (** Dialect whose compilation failed. *)
    ; error : Compile_error.t (** Structural compilation error. *)
    }

  (** Raised by static constructors ending in [_exn]. *)
  exception Definition_error of definition_error

  (** A runtime input that could not be converted into bind parameters. *)
  type binding_error =
    { name : string option (** Optional name assigned when declaring the slot. *)
    ; message : string (** Human-readable validation failure. *)
    }

  (** Failures produced while resolving or rendering a statement for one
      concrete input and dialect. *)
  type sql_error =
    | Unsupported_dialect of Dialect.t
    (** The statement has no precompiled plan for the requested dialect. *)
    | Dynamic_input_required
    (** The statement is dynamic or selects a branch from input, so its SQL
        shape cannot be chosen without [input]. *)
    | Invalid_parameter of binding_error
    (** A runtime parameter failed validation before execution. *)
    | Compilation_error of definition_error
    (** Building a dynamic statement for the supplied input failed. *)

  (** Runtime input slots for one statement. Each getter is retained in the
      compiled statement and applied to the input supplied to [sql] or an
      execution adapter. Reusing the returned expression reuses one bind slot. *)
  type ('input, 'requirements) parameters = private
    { expr :
        'value.
        ?name:string
        -> 'value Db_type.t
        -> get:('input -> 'value)
        -> ('value, 'requirements) Expr.t
      (** Declare a typed bind slot read from ['input]. Reusing the returned
          expression reuses the same slot and parameter index. *)
    ; column :
        'row 'base 'value.
        ?name:string
        -> ('row, 'base, 'value) Column.t
        -> get:('input -> 'value)
        -> ('value, 'requirements) Expr.t
      (** Declare a bind slot using a column's database type. *)
    ; non_negative_int :
        name:string -> get:('input -> int) -> 'requirements Pagination_parameter.t
      (** Declare a pagination slot. Binding fails before execution when the
          getter returns a negative integer. *)
    }

  (** Static statements compiled immediately for PostgreSQL and SQLite.
      Constructors return definition errors; their [_exn] forms raise
      [Definition_error] for the same failures. Runtime cardinality failures
      remain adapter errors. *)
  module Portable : sig
    (** Compile a row-returning statement for both portable dialects. Any
        cardinality proof is accepted and execution returns every row. *)
    val query_many
      :  (('input, Dialect.portable) parameters
          -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
      -> (('input, 'row list, Dialect.portable) t, definition_error) Result.t

    (** Build a statement whose SELECT is statically known to return one row.
        Only [Cardinality.exactly_one] is accepted. Adapters still reject an unexpected
        zero-row or multi-row driver result. Use [expect_one] when the query has
        no static proof. *)
    val query_one
      :  (('input, Dialect.portable) parameters
          -> ( 'row
               , 'kind
               , ([> `Exactly_one ] as 'cardinality)
               , Dialect.portable )
               Result_query.t)
      -> (('input, 'row, Dialect.portable) t, definition_error) Result.t

    (** Build a statement whose SELECT is statically known to return at most
        one row. [Cardinality.exactly_one] is also accepted. Execution returns
        [None] for no row and adapters reject an unexpected multi-row result. *)
    val query_optional
      :  (('input, Dialect.portable) parameters
          -> ( 'row
               , 'kind
               , ([> `At_most_one ] as 'cardinality)
               , Dialect.portable )
               Result_query.t)
      -> (('input, 'row option, Dialect.portable) t, definition_error) Result.t

    (** Compile any row-returning query with the runtime contract that exactly
        one row must be returned. Adapters report an error for zero or multiple
        rows. This is useful when uniqueness is a database or application
        invariant not represented by the DSL. *)
    val expect_one
      :  (('input, Dialect.portable) parameters
          -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
      -> (('input, 'row, Dialect.portable) t, definition_error) Result.t

    (** Build an optional-row statement with an explicit runtime cardinality
        check. Adapters return [None] for zero rows and report an error for more
        than one row. *)
    val expect_optional
      :  (('input, Dialect.portable) parameters
          -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
      -> (('input, 'row option, Dialect.portable) t, definition_error) Result.t

    (** Compile a portable command returning its affected-row result. *)
    val command
      :  (('input, Dialect.portable) parameters -> Dialect.portable Command.t)
      -> (('input, Affected_rows.t, Dialect.portable) t, definition_error) Result.t

    (** Raising form of [query_many]. *)
    val query_many_exn
      :  (('input, Dialect.portable) parameters
          -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
      -> ('input, 'row list, Dialect.portable) t

    (** Raising form of [query_one]. *)
    val query_one_exn
      :  (('input, Dialect.portable) parameters
          -> ( 'row
               , 'kind
               , ([> `Exactly_one ] as 'cardinality)
               , Dialect.portable )
               Result_query.t)
      -> ('input, 'row, Dialect.portable) t

    (** Raising form of [query_optional]. *)
    val query_optional_exn
      :  (('input, Dialect.portable) parameters
          -> ( 'row
               , 'kind
               , ([> `At_most_one ] as 'cardinality)
               , Dialect.portable )
               Result_query.t)
      -> ('input, 'row option, Dialect.portable) t

    (** Raising form of [expect_one]. *)
    val expect_one_exn
      :  (('input, Dialect.portable) parameters
          -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
      -> ('input, 'row, Dialect.portable) t

    (** Raising form of [expect_optional]. *)
    val expect_optional_exn
      :  (('input, Dialect.portable) parameters
          -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
      -> ('input, 'row option, Dialect.portable) t

    (** Raising form of [command]. *)
    val command_exn
      :  (('input, Dialect.portable) parameters -> Dialect.portable Command.t)
      -> ('input, Affected_rows.t, Dialect.portable) t
  end

  (** Static statements compiled immediately for one dialect selected by its
      typed witness. The callback may use operations required by that dialect.
      Constructors return definition errors; their [_exn] forms raise
      [Definition_error] for the same failures. *)
  module For_dialect : sig
    (** Compile a row-returning statement for [dialect]. Any cardinality proof
        is accepted and execution returns every row. *)
    val query_many
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ('row, 'kind, 'cardinality, 'requirements) Result_query.t)
      -> (('input, 'row list, 'requirements) t, definition_error) Result.t

    (** Compile a [Cardinality.exactly_one] query for [dialect]. Adapters retain
        the defensive runtime cardinality check. *)
    val query_one
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ( 'row
               , 'kind
               , ([> `Exactly_one ] as 'cardinality)
               , 'requirements )
               Result_query.t)
      -> (('input, 'row, 'requirements) t, definition_error) Result.t

    (** Build a statement whose SELECT is statically known to return at most
        one row for [dialect]. [Cardinality.exactly_one] is also accepted. *)
    val query_optional
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ( 'row
               , 'kind
               , ([> `At_most_one ] as 'cardinality)
               , 'requirements )
               Result_query.t)
      -> (('input, 'row option, 'requirements) t, definition_error) Result.t

    (** Compile any row-returning query for [dialect] and require exactly one
        row at execution time. *)
    val expect_one
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ('row, 'kind, 'cardinality, 'requirements) Result_query.t)
      -> (('input, 'row, 'requirements) t, definition_error) Result.t

    (** Compile any row-returning query for [dialect] and require at most one
        row at execution time. *)
    val expect_optional
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ('row, 'kind, 'cardinality, 'requirements) Result_query.t)
      -> (('input, 'row option, 'requirements) t, definition_error) Result.t

    (** Compile a command for [dialect]. *)
    val command
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters -> 'requirements Command.t)
      -> (('input, Affected_rows.t, 'requirements) t, definition_error) Result.t

    (** Raising form of [query_many]. *)
    val query_many_exn
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ('row, 'kind, 'cardinality, 'requirements) Result_query.t)
      -> ('input, 'row list, 'requirements) t

    (** Raising form of [query_one]. *)
    val query_one_exn
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ( 'row
               , 'kind
               , ([> `Exactly_one ] as 'cardinality)
               , 'requirements )
               Result_query.t)
      -> ('input, 'row, 'requirements) t

    (** Raising form of [query_optional]. *)
    val query_optional_exn
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ( 'row
               , 'kind
               , ([> `At_most_one ] as 'cardinality)
               , 'requirements )
               Result_query.t)
      -> ('input, 'row option, 'requirements) t

    (** Raising form of [expect_one]. *)
    val expect_one_exn
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ('row, 'kind, 'cardinality, 'requirements) Result_query.t)
      -> ('input, 'row, 'requirements) t

    (** Raising form of [expect_optional]. *)
    val expect_optional_exn
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters
          -> ('row, 'kind, 'cardinality, 'requirements) Result_query.t)
      -> ('input, 'row option, 'requirements) t

    (** Raising form of [command]. *)
    val command_exn
      :  dialect:'requirements Dialect.witness
      -> (('input, 'requirements) parameters -> 'requirements Command.t)
      -> ('input, Affected_rows.t, 'requirements) t
  end

  (** Statements whose SQL shape depends on the runtime input. Constructors do
      not invoke the callback or compile a plan. *)
  module Dynamic : sig
    (** Constructors retain a pure callback without invoking it. Each [sql] or
        adapter [run] invokes it once and compiles for the selected dialect,
        without caching. Values supplied to the DSL remain bound parameters
        of that invocation, including values passed through [Expr.constant].
        Compilation failures are returned at execution time; exceptions raised
        by the callback propagate unchanged. Result cardinality is checked by
        the adapter. *)
    module Portable : sig
      (** Build and compile a portable query from each runtime input. Any
          cardinality proof is accepted and execution returns every row. *)
      val query_many
        :  ('input -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
        -> ('input, 'row list, Dialect.portable) t

      (** Build a [Cardinality.exactly_one] query from each runtime input.
          Compilation validates the proof before the adapter executes it. *)
      val query_one
        :  ('input
            -> ( 'row
                 , 'kind
                 , ([> `Exactly_one ] as 'cardinality)
                 , Dialect.portable )
                 Result_query.t)
        -> ('input, 'row, Dialect.portable) t

      (** Build a [Cardinality.at_most_one] or [Cardinality.exactly_one] query
          from each runtime input. *)
      val query_optional
        :  ('input
            -> ( 'row
                 , 'kind
                 , ([> `At_most_one ] as 'cardinality)
                 , Dialect.portable )
                 Result_query.t)
        -> ('input, 'row option, Dialect.portable) t

      (** Build any row-returning query from the input and require exactly one
          row at execution time. *)
      val expect_one
        :  ('input -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
        -> ('input, 'row, Dialect.portable) t

      (** Build any row-returning query from the input and require at most one
          row at execution time. *)
      val expect_optional
        :  ('input -> ('row, 'kind, 'cardinality, Dialect.portable) Result_query.t)
        -> ('input, 'row option, Dialect.portable) t

      (** Build and compile a portable command from each runtime input. *)
      val command
        :  ('input -> Dialect.portable Command.t)
        -> ('input, Affected_rows.t, Dialect.portable) t
    end
  end

  (** Select between two statement branches for the current
      input. Calls can be nested when more than two finite variants are
      required. Only the selected branch is resolved; dynamic branches are
      supported. *)
  val choose
    :  when_:('input -> bool)
    -> if_true:('input, 'output, 'requirements) t
    -> if_false:('input, 'output, 'requirements) t
    -> ('input, 'output, 'requirements) t

  (** Render the selected plan. For a static statement, [input] may be omitted:
      the SQL template is read from the precompiled dialect plan without
      evaluating parameter getters. Dynamic statements and [choose] require
      [input] because it determines the SQL shape. When supplied, [input] is
      also used to validate static parameter bindings. *)
  val sql
    :  dialect:Dialect.t
    -> ?input:'input
    -> ('input, 'output, 'requirements) t
    -> (string, sql_error) Result.t

  (** Render as [sql], raising when required input is omitted, a supplied input
      fails parameter validation, or the statement does not support the
      selected dialect. Dynamic compilation failures raise [Definition_error]. *)
  val sql_exn
    :  dialect:Dialect.t
    -> ?input:'input
    -> ('input, 'output, 'requirements) t
    -> string
end
