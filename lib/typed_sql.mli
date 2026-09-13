open! Base

(** Build typed SELECT, INSERT, UPDATE and DELETE queries without executing
    them. Pass a finished query to an execution adapter, or compile it to inspect
    its SQL. Values are bound as parameters; connections belong to adapters. *)

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
  (** An occurrence of a table in one query. Values are created by [Query.from];
      an escaped reference from another query is rejected by the compiler. *)
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
  type 'a t
end

(** SQL predicates and boolean composition. *)
module Condition : sig
  (** A predicate using SQL three-valued logic. *)
  type t

  (** A predicate that always evaluates to SQL [TRUE]. Normalization removes it
      when it is an identity element. *)
  val true_ : t

  (** A predicate that always evaluates to SQL [FALSE]. Normalization folds
      surrounding boolean expressions when possible. *)
  val false_ : t

  (** Negate a predicate using SQL [NOT]. *)
  val not_ : t -> t

  (** Infix composition for SQL predicates. *)
  module Infix : sig
    (** SQL conjunction. *)
    val ( &&. ) : t -> t -> t

    (** SQL disjunction. *)
    val ( ||. ) : t -> t -> t
  end
end

(** Typed scalar SQL expressions and comparisons. *)
module Expr : sig
  (** A typed scalar SQL expression. *)
  type 'a t

  (** Refer to a column from a regular table occurrence. The phantom row type
      prevents using a column declared for another table descriptor. *)
  val column : 'row Table_ref.t -> ('row, 'base, 'value) Column.t -> 'value t

  (** A column selected through the nullable side of a LEFT JOIN. Existing
      schema nullability is flattened, so the result contains one [option]. *)
  val nullable_column
    :  'row Nullable_table_ref.t
    -> ('row, 'base, 'value) Column.t
    -> 'base option t

  (** Treat an expression as nullable without changing its SQL. This is useful
      for null checks on a non-nullable expression. *)
  val to_nullable : 'a t -> 'a option t

  (** Create a bound parameter. The value never becomes part of rendered SQL. *)
  val param : 'a Db_type.t -> 'a -> 'a t

  (** Test a nullable expression with SQL [IS NULL]. *)
  val is_null : 'a option t -> Condition.t

  (** Test a nullable expression with SQL [IS NOT NULL]. *)
  val is_not_null : 'a option t -> Condition.t

  (** Test whether an expression equals one of the bound values. An empty list
      is normalized to SQL [FALSE]. *)
  val in_ : 'a t -> 'a list -> Condition.t

  (** Test whether an expression differs from every bound value. An empty list
      is normalized to SQL [TRUE]. As in SQL, a [NULL] in a non-empty list can
      make the predicate unknown. *)
  val not_in : 'a t -> 'a list -> Condition.t

  (** Test membership against typed SQL expressions instead of OCaml values. *)
  val in_exprs : 'a t -> 'a t list -> Condition.t

  (** Test non-membership against typed SQL expressions. *)
  val not_in_exprs : 'a t -> 'a t list -> Condition.t

  (** Test whether an expression lies inside an inclusive range whose bounds
      are bound parameters. *)
  val between : 'a t -> lower:'a -> upper:'a -> Condition.t

  (** Test an inclusive range using SQL expressions as both bounds. *)
  val between_exprs : 'a t -> lower:'a t -> upper:'a t -> Condition.t

  (** Compare values with null-safe SQL semantics. PostgreSQL uses [IS DISTINCT
      FROM], while SQLite uses its equivalent [IS NOT] operator. *)
  val is_distinct_from : 'a t -> 'a t -> Condition.t

  (** Null-safe comparison with a bound OCaml value. *)
  val is_distinct_from_value : 'a t -> 'a -> Condition.t

  (** Build a searched SQL [CASE]. Conditions are tested in list order. An
      empty branch list yields [else_] directly at execution. All branch
      expressions have the same OCaml and database type. *)
  val case : (Condition.t * 'a t) list -> else_:'a t -> 'a t

  (** Convert text to lowercase using the database's portable scalar
      function. *)
  val lower : string t -> string t

  (** Convert text to uppercase. *)
  val upper : string t -> string t

  (** Return the number of characters in text. Lowering uses [CHAR_LENGTH] on
      PostgreSQL and [LENGTH] on SQLite. *)
  val length : string t -> int t

  (** Concatenate two text expressions with SQL [||]. *)
  val concat : string t -> string t -> string t

  (** Concatenate text with a bound OCaml string. *)
  val concat_value : string t -> string -> string t

  (** Count rows in the current aggregate group. *)
  val count_all : int64 t

  (** Count non-null values of an expression. *)
  val count : 'a t -> int64 t

  (** Count distinct non-null values of an expression. *)
  val count_distinct : 'a t -> int64 t

  (** Embed a one-column SELECT as a scalar expression. The database still
      enforces that execution returns at most one row. *)
  val scalar_subquery : 'a Scalar_query.t -> 'a t

  (** The transaction's current timestamp. Both supported dialects render the
      standard SQL [CURRENT_TIMESTAMP] expression. *)
  val current_timestamp : Ptime.t t

  (** Type-safe arithmetic over SQL integers represented as OCaml [int]. *)
  module Int : sig
    val add : int t -> int t -> int t
    val subtract : int t -> int t -> int t
    val multiply : int t -> int t -> int t
    val divide : int t -> int t -> int t

    module Infix : sig
      val ( +. ) : int t -> int t -> int t
      val ( -. ) : int t -> int t -> int t
      val ( *. ) : int t -> int t -> int t
      val ( /. ) : int t -> int t -> int t
    end
  end

  (** Type-safe arithmetic over SQL integers represented as OCaml [int64]. *)
  module Int64 : sig
    val add : int64 t -> int64 t -> int64 t
    val subtract : int64 t -> int64 t -> int64 t
    val multiply : int64 t -> int64 t -> int64 t
    val divide : int64 t -> int64 t -> int64 t

    module Infix : sig
      val ( +. ) : int64 t -> int64 t -> int64 t
      val ( -. ) : int64 t -> int64 t -> int64 t
      val ( *. ) : int64 t -> int64 t -> int64 t
      val ( /. ) : int64 t -> int64 t -> int64 t
    end
  end

  (** Type-safe arithmetic over SQL floating-point values. *)
  module Float : sig
    val add : float t -> float t -> float t
    val subtract : float t -> float t -> float t
    val multiply : float t -> float t -> float t
    val divide : float t -> float t -> float t

    module Infix : sig
      val ( +. ) : float t -> float t -> float t
      val ( -. ) : float t -> float t -> float t
      val ( *. ) : float t -> float t -> float t
      val ( /. ) : float t -> float t -> float t
    end
  end

  (** Operators are the primary API for constructing comparisons. Operators with
      a dot compare expressions; operators ending with [$] bind an OCaml value
      using the type carried by the left expression. *)
  module Infix : sig
    (** SQL equality between two expressions. *)
    val ( =. ) : 'a t -> 'a t -> Condition.t

    (** SQL inequality between two expressions. *)
    val ( <>. ) : 'a t -> 'a t -> Condition.t

    (** SQL less-than comparison between two expressions. *)
    val ( <. ) : 'a t -> 'a t -> Condition.t

    (** SQL less-than-or-equal comparison between two expressions. *)
    val ( <=. ) : 'a t -> 'a t -> Condition.t

    (** SQL greater-than comparison between two expressions. *)
    val ( >. ) : 'a t -> 'a t -> Condition.t

    (** SQL greater-than-or-equal comparison between two expressions. *)
    val ( >=. ) : 'a t -> 'a t -> Condition.t

    (** SQL equality with a bound OCaml value. *)
    val ( =$ ) : 'a t -> 'a -> Condition.t

    (** SQL inequality with a bound OCaml value. *)
    val ( <>$ ) : 'a t -> 'a -> Condition.t

    (** SQL less-than comparison with a bound OCaml value. *)
    val ( <$ ) : 'a t -> 'a -> Condition.t

    (** SQL less-than-or-equal comparison with a bound OCaml value. *)
    val ( <=$ ) : 'a t -> 'a -> Condition.t

    (** SQL greater-than comparison with a bound OCaml value. *)
    val ( >$ ) : 'a t -> 'a -> Condition.t

    (** SQL greater-than-or-equal comparison with a bound OCaml value. *)
    val ( >=$ ) : 'a t -> 'a -> Condition.t

    (** SQL [LIKE] between text expressions. *)
    val ( =~. ) : string t -> string t -> Condition.t

    (** SQL [LIKE] with a bound pattern. Wildcards are interpreted by the
        database and are not escaped by typed-sql. *)
    val ( =~$ ) : string t -> string -> Condition.t
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

(** Applicative result projections. *)
module Projection : sig
  (** An applicative description of SELECT expressions and their result
      decoder. A standalone [return] projection is rejected because SQL SELECT must
      contain at least one expression. *)
  type 'a t

  (** Standard applicative operations. [return] contributes no SQL expression;
      [map] changes only decoding; [both], [map2], [map3], [apply], and [all]
      concatenate selected expressions from left to right. *)
  include Base.Applicative.S with type 'a t := 'a t

  (** Add one typed SQL expression and decode its field unchanged. *)
  val expr : 'a Expr.t -> 'a t

  (** Select two expressions from left to right and decode them as a pair. *)
  val pair : 'a Expr.t -> 'b Expr.t -> ('a * 'b) t

  (** Syntax support for applicative [let%map] and parallel [and] bindings. *)
  module Let_syntax : sig
    (** The same operation as [Projection.return]. *)
    val return : 'a -> 'a t

    (** Infix applicative operators supplied by Base. *)
    include Base.Applicative.Applicative_infix with type 'a t := 'a t

    (** Operations consumed by [ppx_let]. Application code normally opens the
        outer [Projection.Let_syntax] module. *)
    module Let_syntax : sig
      (** Lift a decoded constant without adding a SELECT expression. *)
      val return : 'a -> 'a t

      (** Transform a decoded projection result. *)
      val map : 'a t -> f:('a -> 'b) -> 'b t

      (** Combine two projections in left-to-right SELECT order. *)
      val both : 'a t -> 'b t -> ('a * 'b) t

      (** Scope opened on the right-hand side of [let%map] bindings. *)
      module Open_on_rhs : sig end
    end
  end
end

(** Finished statements that decode returned rows. *)
module Result_query : sig
  (** A deferred statement that returns decoded rows. *)
  type 'result t
end

(** Finished statements that return only an affected-row result. *)
module Command : sig
  (** A deferred INSERT, UPDATE, or DELETE statement without returned rows. *)
  type t
end

(** Immutable SELECT builders. *)
module Query : sig
  (** An immutable SELECT builder. ['ctx] is the callback context of visible
      table references. [select] finishes the builder and determines the result
      type. *)
  type 'ctx t

  (** Direction for one [ORDER BY] key. *)
  type direction =
    [ `Asc (** Ascending SQL order. *)
    | `Desc (** Descending SQL order. *)
    ]

  (** Start a SELECT builder from one table. Subsequent callbacks receive the
      only valid reference to this occurrence. *)
  val from : 'row Table.t -> 'row Table_ref.t t

  (** Finish the builder with a result projection. Keeping [select] last avoids
      a temporary projection while filters and joins are assembled. *)
  val select : ('ctx -> 'result Projection.t) -> 'ctx t -> 'result Result_query.t

  (** Finish a builder as a one-expression query suitable for a scalar
      subquery or [IN] predicate. *)
  val select_scalar : ('ctx -> 'value Expr.t) -> 'ctx t -> 'value Scalar_query.t

  (** Test whether an unfinished SELECT returns at least one row. Its
      projection is intentionally omitted and rendered as [SELECT 1]. The
      query may capture references from the enclosing callback. *)
  val exists : 'inner_ctx t -> Condition.t

  (** Negated [EXISTS]. *)
  val not_exists : 'inner_ctx t -> Condition.t

  (** Test membership in a typed one-column SELECT. *)
  val in_subquery : 'a Expr.t -> 'a Scalar_query.t -> Condition.t

  (** Test non-membership in a typed one-column SELECT. *)
  val not_in_subquery : 'a Expr.t -> 'a Scalar_query.t -> Condition.t

  (** Append an [INNER JOIN]. The [on] callback sees the existing context and a
      regular reference to the newly joined table. *)
  val inner_join
    :  'row Table.t
    -> on:('ctx -> 'row Table_ref.t -> Condition.t)
    -> 'ctx t
    -> ('ctx * 'row Table_ref.t) t

  (** [on] sees the new table before null extension. Subsequent callbacks
      receive a nullable reference and must use [Expr.nullable_column]. *)
  val left_join
    :  'row Table.t
    -> on:('ctx -> 'row Table_ref.t -> Condition.t)
    -> 'ctx t
    -> ('ctx * 'row Nullable_table_ref.t) t

  (** Repeated calls combine predicates with SQL AND. *)
  val where : ('ctx -> Condition.t) -> 'ctx t -> 'ctx t

  (** Add a predicate only when the optional value is [Some]. [None] returns
      the same immutable query unchanged. *)
  val where_opt : 'value option -> f:('ctx -> 'value -> Condition.t) -> 'ctx t -> 'ctx t

  (** Remove duplicate result rows with portable SQL [DISTINCT]. *)
  val distinct : 'ctx t -> 'ctx t

  (** Append one [GROUP BY] expression. Repeated calls preserve call order. *)
  val group_by : ('ctx -> 'value Expr.t) -> 'ctx t -> 'ctx t

  (** Add an aggregate-group predicate. Repeated calls combine predicates with
      SQL [AND]. The compiler rejects ungrouped non-aggregate expressions. *)
  val having : ('ctx -> Condition.t) -> 'ctx t -> 'ctx t

  (** Append one ordering key. Repeated calls preserve call order. *)
  val order_by : ('ctx -> 'value Expr.t) -> direction -> 'ctx t -> 'ctx t

  (** Set the maximum number of returned rows. The compiler rejects negative
      values. A later call replaces the previous limit. *)
  val limit : int -> 'ctx t -> 'ctx t

  (** Set the number of rows to skip. The compiler rejects negative values. A
      later call replaces the previous offset. *)
  val offset : int -> 'ctx t -> 'ctx t
end

(** Immutable INSERT builders. *)
module Insert : sig
  (** An INSERT builder. The compiler rejects empty rows, duplicate target
      columns, and different column sets across rows. Values passed to [set]
      are always bound. *)
  type 'row t

  (** Start an INSERT containing one empty row. *)
  val into : 'row Table.t -> 'row t

  (** Assign a column from an OCaml value, which is always bound as a
      parameter. *)
  val set : ('row, 'base, 'value) Column.t -> 'value -> 'row t -> 'row t

  (** Assign a column from a typed expression. The compiler rejects an
      expression referring to a different source. *)
  val set_expr : ('row, 'base, 'value) Column.t -> 'value Expr.t -> 'row t -> 'row t

  (** Assign SQL [DEFAULT] to a column without inventing an OCaml value. SQLite
      rejects this operation explicitly because it does not support [DEFAULT]
      inside a [VALUES] row. *)
  val default : ('row, 'base, 'value) Column.t -> 'row t -> 'row t

  (** Build a multi-row INSERT. Each function receives an empty row builder.
      Rows may call [set], [set_expr], or [default] in any order, but every row
      must assign the same set of columns. *)
  val rows : 'row Table.t -> ('row t -> 'row t) list -> 'row t

  (** Ignore rows rejected by a unique or exclusion conflict. PostgreSQL and
      SQLite both render [ON CONFLICT DO NOTHING]; other integrity errors still
      fail through the execution adapter. *)
  val on_conflict_do_nothing : 'row t -> 'row t

  (** Finish an INSERT without returned rows. Compilation rejects an empty or
      duplicate assignment list. *)
  val command : 'row t -> Command.t

  (** Finish an INSERT with a typed [RETURNING] projection. *)
  val returning
    :  ('row Table_ref.t -> 'result Projection.t)
    -> 'row t
    -> 'result Result_query.t
end

(** Immutable UPDATE builders with type-level row-scope authorization. *)
module Update : sig
  (** Marker for an UPDATE that cannot yet be finalized. *)
  type unscoped

  (** Marker for an UPDATE authorized by [where] or [all_rows]. *)
  type scoped

  (** Only builders scoped by [where] or [all_rows] can be finalized. *)
  type ('row, 'scope) t

  (** Start an UPDATE without assignments or row scope. *)
  val table : 'row Table.t -> ('row, unscoped) t

  (** Assign a column from an OCaml value, which is always bound as a
      parameter. *)
  val set
    :  ('row, 'base, 'value) Column.t
    -> 'value
    -> ('row, 'scope) t
    -> ('row, 'scope) t

  (** Assign a column from a typed expression. The compiler rejects an
      expression referring to another query source. *)
  val set_expr
    :  ('row, 'base, 'value) Column.t
    -> 'value Expr.t
    -> ('row, 'scope) t
    -> ('row, 'scope) t

  (** Assign SQL [DEFAULT] to a column. PostgreSQL supports this operation;
      compilation for SQLite returns [Compile_error.Unsupported_operation]. *)
  val default : ('row, 'base, 'value) Column.t -> ('row, 'scope) t -> ('row, 'scope) t

  (** Conditionally bind and assign a value. [None] leaves the builder
      unchanged. For a nullable column, [Some None] writes SQL [NULL]. *)
  val set_opt
    :  ('row, 'base, 'value) Column.t
    -> 'value option
    -> ('row, 'scope) t
    -> ('row, 'scope) t

  (** Conditionally assign an expression. [None] leaves the builder unchanged. *)
  val set_expr_opt
    :  ('row, 'base, 'value) Column.t
    -> 'value Expr.t option
    -> ('row, 'scope) t
    -> ('row, 'scope) t

  (** Add one table to [UPDATE ... FROM] and configure the update while its
      reference is in lexical scope. The callback receives the target, the new
      source, and the current immutable builder. Repeated calls append sources. *)
  val from
    :  'source Table.t
    -> f:
         ('row Table_ref.t
          -> 'source Table_ref.t
          -> ('row, 'scope) t
          -> ('row, 'new_scope) t)
    -> ('row, 'scope) t
    -> ('row, 'new_scope) t

  (** Add a row predicate and mark the UPDATE as scoped. Repeated calls combine
      predicates with SQL [AND]. *)
  val where : ('row Table_ref.t -> Condition.t) -> ('row, 'scope) t -> ('row, scoped) t

  (** Explicitly authorize updating every row, removing any previous filter. *)
  val all_rows : ('row, 'scope) t -> ('row, scoped) t

  (** Finish a scoped UPDATE without returned rows. Compilation rejects an
      empty or duplicate assignment list. *)
  val command : ('row, scoped) t -> Command.t

  (** Finish a scoped UPDATE with a typed [RETURNING] projection. *)
  val returning
    :  ('row Table_ref.t -> 'result Projection.t)
    -> ('row, scoped) t
    -> 'result Result_query.t
end

(** Immutable DELETE builders with type-level row-scope authorization. *)
module Delete : sig
  (** Marker for a DELETE that cannot yet be finalized. *)
  type unscoped

  (** Marker for a DELETE authorized by [where] or [all_rows]. *)
  type scoped

  (** Only builders scoped by [where] or [all_rows] can be finalized. *)
  type ('row, 'scope) t

  (** Start a DELETE without row scope. *)
  val from : 'row Table.t -> ('row, unscoped) t

  (** Add a row predicate and mark the DELETE as scoped. Repeated calls combine
      predicates with SQL [AND]. *)
  val where : ('row Table_ref.t -> Condition.t) -> ('row, 'scope) t -> ('row, scoped) t

  (** Explicitly authorize deleting every row, removing any previous filter. *)
  val all_rows : ('row, 'scope) t -> ('row, scoped) t

  (** Finish a scoped DELETE without returned rows. *)
  val command : ('row, scoped) t -> Command.t

  (** Finish a scoped DELETE with a typed [RETURNING] projection. *)
  val returning
    :  ('row Table_ref.t -> 'result Projection.t)
    -> ('row, scoped) t
    -> 'result Result_query.t
end

(** Supported SQL dialects. *)
module Dialect : sig
  (** SQL rendering rules selected during pure compilation. *)
  type t =
    | Postgresql (** PostgreSQL quoting and [$n] placeholders. *)
    | Sqlite (** SQLite quoting and [?n] placeholders. *)

  (** Return the stable lowercase dialect name used in diagnostics. *)
  val to_string : t -> string
end

(** Errors returned by pure compilation. *)
module Compile_error : sig
  (** A structural error found after query normalization and before SQL is
      exposed to an adapter. *)
  type t =
    | Empty_projection
    (** SELECT or RETURNING has no SQL expression. Applicative constants alone
          do not form a valid projection. *)
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
    (** An aggregate appears in [WHERE], [JOIN ON], or [GROUP BY]. The string
        names the rejected SQL clause. *)
    | Nested_aggregate (** One aggregate expression is used inside another aggregate. *)
    | Ungrouped_expression
    (** An aggregate query selects, orders, or filters by a non-aggregate
        expression whose columns are absent from [GROUP BY]. *)

  (** Format a compilation error for a user. *)
  val pp : Formatter.t -> t -> unit

  (** Return a human-readable compilation error. *)
  val to_string : t -> string
end

(** Validated and rendered statements that return rows. *)
module Compiled_query : sig
  (** A validated query. SQL contains placeholders, never interpolated values. *)
  type 'result t = 'result Typed_sql_private.Compiled_query.t

  (** Return the dialect used to compile the query. *)
  val dialect : 'result t -> Dialect.t

  (** Render SQL with dialect-specific placeholders. Bound values remain
      available only to execution adapters. *)
  val sql : 'result t -> string
end

(** Validated and rendered statements without returned rows. *)
module Compiled_command : sig
  (** A compiled statement without a row decoder. *)
  type t = Typed_sql_private.Compiled_command.t

  (** Return the dialect used to compile the command. *)
  val dialect : t -> Dialect.t

  (** Render SQL with dialect-specific placeholders. Bound values remain
      available only to execution adapters. *)
  val sql : t -> string
end

(** Backend-independent affected-row results. *)
module Affected_rows : sig
  (** [Unknown] means that the backend cannot report the count, not that zero
      rows were affected. *)
  type t =
    | Known of int (** The backend reported an exact number of changed rows. *)
    | Unknown (** The backend completed the command but cannot report an exact count. *)

  (** Format an affected-row result. *)
  val pp : Formatter.t -> t -> unit
end

(** Pure query validation and SQL compilation. *)
module Compiler : sig
  (** Pure compilation: assigns deterministic aliases and bind slots, and
      reports invalid input without performing database operations. *)
  val compile
    :  dialect:Dialect.t
    -> 'result Result_query.t
    -> ('result Compiled_query.t, Compile_error.t) Result.t

  (** Purely validate and compile a command without returned rows. *)
  val compile_command
    :  dialect:Dialect.t
    -> Command.t
    -> (Compiled_command.t, Compile_error.t) Result.t
end
