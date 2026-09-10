open! Base

(** Build typed SELECT, INSERT, UPDATE and DELETE queries without executing
    them. Pass a finished query to an execution adapter, or compile it to inspect
    its SQL. Values are bound as parameters; connections belong to adapters. *)

module Identifier : sig
  (** A validated, unquoted SQL identifier. Renderers are responsible for
      dialect-specific quoting. *)
  type t

  type error =
    [ `Empty
    | `Contains_nul
    ]

  val of_string : string -> (t, error) Result.t
  val of_string_exn : string -> t
  val to_string : t -> string
  val equal : t -> t -> bool
  val pp : Formatter.t -> t -> unit
  val error_to_string : error -> string
end

module Db_type : sig
  (** A database representation for an OCaml value. It is independent from any
      execution backend. *)
  type 'a t

  val bool : bool t
  val int : int t
  val int64 : int64 t
  val float : float t
  val text : string t
  val bytes : bytes t
  val option : 'a t -> 'a option t

  val map
    :  ?name:string
    -> encode:('b -> ('a, string) Result.t)
    -> decode:('a -> ('b, string) Result.t)
    -> 'a t
    -> 'b t

  val name : 'a t -> string
end

module Table : sig
  (** A table descriptor. The phantom row type distinguishes schemas at compile
      time and is normally declared abstract inside a generated table module. *)
  type 'row t

  val v : ?schema:Identifier.t -> Identifier.t -> 'row t
  val v_exn : ?schema:string -> string -> 'row t
  val name : 'row t -> Identifier.t
  val schema : 'row t -> Identifier.t Option.t
end

module Column : sig
  (** A column tied to a table's phantom row type. ['base] is the non-null SQL
      value type and ['value] is the value read from a regular table reference. *)
  type ('row, 'base, 'value) t

  val v : 'row Table.t -> Identifier.t -> 'a Db_type.t -> ('row, 'a, 'a) t
  val v_exn : 'row Table.t -> string -> 'a Db_type.t -> ('row, 'a, 'a) t
  val nullable_v : 'row Table.t -> Identifier.t -> 'a Db_type.t -> ('row, 'a, 'a option) t
  val nullable_v_exn : 'row Table.t -> string -> 'a Db_type.t -> ('row, 'a, 'a option) t
  val table : ('row, 'base, 'value) t -> 'row Table.t
  val name : ('row, 'base, 'value) t -> Identifier.t
  val base_db_type : ('row, 'base, 'value) t -> 'base Db_type.t
  val db_type : ('row, 'base, 'value) t -> 'value Db_type.t
end

module Table_ref : sig
  (** An occurrence of a table in one query. Values are created by [Query.from];
      an escaped reference from another query is rejected by the compiler. *)
  type 'row t
end

module Nullable_table_ref : sig
  (** A table occurrence made nullable by an outer join. *)
  type 'row t
end

module Condition : sig
  (** A predicate using SQL three-valued logic. *)
  type t

  val true_ : t
  val false_ : t
  val not_ : t -> t

  module Infix : sig
    val ( &&. ) : t -> t -> t
    val ( ||. ) : t -> t -> t
  end
end

module Expr : sig
  (** A typed scalar SQL expression. *)
  type 'a t

  val column : 'row Table_ref.t -> ('row, 'base, 'value) Column.t -> 'value t

  (** A column selected through the nullable side of a LEFT JOIN. Existing
      schema nullability is flattened, so the result contains one [option]. *)
  val nullable_column
    :  'row Nullable_table_ref.t
    -> ('row, 'base, 'value) Column.t
    -> 'base option t

  val to_nullable : 'a t -> 'a option t
  val param : 'a Db_type.t -> 'a -> 'a t
  val is_null : 'a option t -> Condition.t
  val is_not_null : 'a option t -> Condition.t

  (** Operators are the primary API for constructing comparisons. Operators with
      a dot compare expressions; operators ending with [$] bind an OCaml value
      using the type carried by the left expression. *)
  module Infix : sig
    val ( =. ) : 'a t -> 'a t -> Condition.t
    val ( <>. ) : 'a t -> 'a t -> Condition.t
    val ( <. ) : 'a t -> 'a t -> Condition.t
    val ( <=. ) : 'a t -> 'a t -> Condition.t
    val ( >. ) : 'a t -> 'a t -> Condition.t
    val ( >=. ) : 'a t -> 'a t -> Condition.t
    val ( =$ ) : 'a t -> 'a -> Condition.t
    val ( <>$ ) : 'a t -> 'a -> Condition.t
    val ( <$ ) : 'a t -> 'a -> Condition.t
    val ( <=$ ) : 'a t -> 'a -> Condition.t
    val ( >$ ) : 'a t -> 'a -> Condition.t
    val ( >=$ ) : 'a t -> 'a -> Condition.t
    val ( =~. ) : string t -> string t -> Condition.t
    val ( =~$ ) : string t -> string -> Condition.t
  end
end

module Projection : sig
  (** An applicative description of SELECT expressions and their result
      decoder. A standalone [return] projection is rejected because SQL SELECT must
      contain at least one expression. *)
  type 'a t

  include Base.Applicative.S with type 'a t := 'a t

  val expr : 'a Expr.t -> 'a t

  module Let_syntax : sig
    val return : 'a -> 'a t

    include Base.Applicative.Applicative_infix with type 'a t := 'a t

    module Let_syntax : sig
      val return : 'a -> 'a t
      val map : 'a t -> f:('a -> 'b) -> 'b t
      val both : 'a t -> 'b t -> ('a * 'b) t

      module Open_on_rhs : sig end
    end
  end
end

module Result_query : sig
  (** A deferred statement that returns decoded rows. *)
  type 'result t
end

module Command : sig
  (** A deferred INSERT, UPDATE, or DELETE statement without returned rows. *)
  type t
end

module Query : sig
  (** An immutable deferred SELECT query. ['ctx] is the callback context of
      visible table references and ['result] is the decoded row type. *)
  type ('ctx, 'result) t

  type direction =
    [ `Asc
    | `Desc
    ]

  val from
    :  'row Table.t
    -> select:('row Table_ref.t -> 'result Projection.t)
    -> ('row Table_ref.t, 'result) t

  val select
    :  ('ctx -> 'result Projection.t)
    -> ('ctx, 'old_result) t
    -> ('ctx, 'result) t

  val inner_join
    :  'row Table.t
    -> on:('ctx -> 'row Table_ref.t -> Condition.t)
    -> ('ctx, 'result) t
    -> ('ctx * 'row Table_ref.t, 'result) t

  (** [on] sees the new table before null extension. Subsequent callbacks
      receive a nullable reference and must use [Expr.nullable_column]. *)
  val left_join
    :  'row Table.t
    -> on:('ctx -> 'row Table_ref.t -> Condition.t)
    -> ('ctx, 'result) t
    -> ('ctx * 'row Nullable_table_ref.t, 'result) t

  (** Repeated calls combine predicates with SQL AND. *)
  val where : ('ctx -> Condition.t) -> ('ctx, 'result) t -> ('ctx, 'result) t

  val where_opt
    :  'value option
    -> f:('ctx -> 'value -> Condition.t)
    -> ('ctx, 'result) t
    -> ('ctx, 'result) t

  val order_by
    :  ('ctx -> 'value Expr.t)
    -> direction
    -> ('ctx, 'result) t
    -> ('ctx, 'result) t

  val limit : int -> ('ctx, 'result) t -> ('ctx, 'result) t
  val offset : int -> ('ctx, 'result) t -> ('ctx, 'result) t

  (** Finish the builder for compilation or execution without running SQL. *)
  val to_result : ('ctx, 'result) t -> 'result Result_query.t
end

module Insert : sig
  (** A single-row INSERT builder. The compiler rejects empty assignments and
      duplicate target columns. Values passed to [set] are always bound. *)
  type 'row t

  val into : 'row Table.t -> 'row t
  val set : ('row, 'base, 'value) Column.t -> 'value -> 'row t -> 'row t
  val set_expr : ('row, 'base, 'value) Column.t -> 'value Expr.t -> 'row t -> 'row t
  val command : 'row t -> Command.t

  val returning
    :  ('row Table_ref.t -> 'result Projection.t)
    -> 'row t
    -> 'result Result_query.t
end

module Update : sig
  type unscoped
  type scoped

  (** Only builders scoped by [where] or [all_rows] can be finalized. *)
  type ('row, 'scope) t

  val table : 'row Table.t -> ('row, unscoped) t

  val set
    :  ('row, 'base, 'value) Column.t
    -> 'value
    -> ('row, 'scope) t
    -> ('row, 'scope) t

  val set_expr
    :  ('row, 'base, 'value) Column.t
    -> 'value Expr.t
    -> ('row, 'scope) t
    -> ('row, 'scope) t

  val where : ('row Table_ref.t -> Condition.t) -> ('row, 'scope) t -> ('row, scoped) t

  (** Explicitly authorize updating every row, removing any previous filter. *)
  val all_rows : ('row, 'scope) t -> ('row, scoped) t

  val command : ('row, scoped) t -> Command.t

  val returning
    :  ('row Table_ref.t -> 'result Projection.t)
    -> ('row, scoped) t
    -> 'result Result_query.t
end

module Delete : sig
  type unscoped
  type scoped

  (** Only builders scoped by [where] or [all_rows] can be finalized. *)
  type ('row, 'scope) t

  val from : 'row Table.t -> ('row, unscoped) t
  val where : ('row Table_ref.t -> Condition.t) -> ('row, 'scope) t -> ('row, scoped) t

  (** Explicitly authorize deleting every row, removing any previous filter. *)
  val all_rows : ('row, 'scope) t -> ('row, scoped) t

  val command : ('row, scoped) t -> Command.t

  val returning
    :  ('row Table_ref.t -> 'result Projection.t)
    -> ('row, scoped) t
    -> 'result Result_query.t
end

module Dialect : sig
  type t =
    | Postgresql
    | Sqlite

  val to_string : t -> string
end

module Compile_error : sig
  type t =
    | Empty_projection
    | Foreign_source of
        { visible : int list
        ; actual : int
        }
    | Negative_limit of int
    | Negative_offset of int
    | Empty_assignments of [ `Insert | `Update ]
    | Duplicate_assignment of Identifier.t
    | Invalid_assignment_source of
        { expected : int
        ; actual : int
        }

  val pp : Formatter.t -> t -> unit
  val to_string : t -> string
end

module Compiled_query : sig
  (** A validated query. SQL contains placeholders, never interpolated values. *)
  type 'result t = 'result Typed_sql_private.Compiled_query.t

  val dialect : 'result t -> Dialect.t
  val sql : 'result t -> string
end

module Compiled_command : sig
  (** A compiled statement without a row decoder. *)
  type t = Typed_sql_private.Compiled_command.t

  val dialect : t -> Dialect.t
  val sql : t -> string
end

module Affected_rows : sig
  (** [Unknown] means that the backend cannot report the count, not that zero
      rows were affected. *)
  type t =
    | Known of int
    | Unknown

  val pp : Formatter.t -> t -> unit
end

module Compiler : sig
  (** Pure compilation: assigns deterministic aliases and bind slots, and
      reports invalid input without performing database operations. *)
  val compile
    :  dialect:Dialect.t
    -> 'result Result_query.t
    -> ('result Compiled_query.t, Compile_error.t) Result.t

  val compile_command
    :  dialect:Dialect.t
    -> Command.t
    -> (Compiled_command.t, Compile_error.t) Result.t
end
