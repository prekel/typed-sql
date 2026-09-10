open! Base

(** Backend-independent typed relational query DSL. *)

module Identifier = Identifier
module Db_type = Db_type
module Table = Table
module Column = Column

module Table_ref : sig
  type 'row t = 'row Table_ref.t
end

module Nullable_table_ref : sig
  type 'row t = 'row Nullable_table_ref.t
end

module Condition : sig
  type t = Condition.t

  val true_ : t
  val false_ : t
  val and_ : t -> t -> t
  val or_ : t -> t -> t
  val not_ : t -> t
  val all : t list -> t
  val any : t list -> t

  module Infix : sig
    val ( &&. ) : t -> t -> t
    val ( ||. ) : t -> t -> t
  end
end

module Expr : sig
  type 'a t = 'a Expr.t

  val column : 'row Table_ref.t -> ('row, 'base, 'value) Column.t -> 'value t

  val nullable_column
    :  'row Nullable_table_ref.t
    -> ('row, 'base, 'value) Column.t
    -> 'base option t

  val to_nullable : 'a t -> 'a option t
  val param : 'a Db_type.t -> 'a -> 'a t
  val eq : 'a t -> 'a t -> Condition.t
  val eq_value : 'a t -> 'a -> Condition.t
  val neq : 'a t -> 'a t -> Condition.t
  val neq_value : 'a t -> 'a -> Condition.t
  val lt : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
  val lt_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
  val lte : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
  val lte_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
  val gt : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
  val gt_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
  val gte : 'a Db_type.Ordering.t -> 'a t -> 'a t -> Condition.t
  val gte_value : 'a Db_type.Ordering.t -> 'a t -> 'a -> Condition.t
  val like : string t -> string t -> Condition.t
  val like_value : string t -> string -> Condition.t
  val is_null : 'a option t -> Condition.t
  val is_not_null : 'a option t -> Condition.t
  val db_type : 'a t -> 'a Db_type.t

  module Infix : sig
    val ( =. ) : 'a t -> 'a t -> Condition.t
    val ( =: ) : 'a t -> 'a -> Condition.t
    val ( <>. ) : 'a t -> 'a t -> Condition.t
    val ( <>: ) : 'a t -> 'a -> Condition.t
  end
end

module Projection : sig
  type 'a t = 'a Projection.t

  type 'a view = 'a Projection.view =
    | Pure : 'a -> 'a view
    | Expr : 'a Expr.t -> 'a view
    | Map : ('a -> 'b) * 'a t -> 'b view
    | Both : 'a t * 'b t -> ('a * 'b) view

  val pure : 'a -> 'a t
  val expr : 'a Expr.t -> 'a t
  val map : ('a -> 'b) -> 'a t -> 'b t
  val both : 'a t -> 'b t -> ('a * 'b) t
  val map2 : ('a -> 'b -> 'c) -> 'a t -> 'b t -> 'c t
  val map3 : ('a -> 'b -> 'c -> 'd) -> 'a t -> 'b t -> 'c t -> 'd t
  val view : 'a t -> 'a view
end

module Query : sig
  type ('ctx, 'result) t = ('ctx, 'result) Query.t

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

  val left_join
    :  'row Table.t
    -> on:('ctx -> 'row Table_ref.t -> Condition.t)
    -> ('ctx, 'result) t
    -> ('ctx * 'row Nullable_table_ref.t, 'result) t

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
  val to_result : ('ctx, 'result) t -> 'result Result_query.t
end

module Result_query : sig
  type 'result t = 'result Result_query.t
end

module Command : sig
  type t = Command.t
end

module Insert = Insert
module Update = Update
module Delete = Delete
module Dialect = Dialect

module Template : sig
  type part = Template.part =
    | Text of string
    | Param of int

  type t = Template.t

  val parts : t -> part list
  val to_sql : dialect:Dialect.t -> t -> string
end

module Shape : sig
  type t = Shape.t

  val equal : t -> t -> bool
  val hash : t -> int
  val pp : Formatter.t -> t -> unit
  val to_string : t -> string
end

module Compile_error = Compile_error

module Compiled_query : sig
  type 'result t = 'result Compiled_query.t

  val dialect : 'result t -> Dialect.t
  val template : 'result t -> Template.t
  val parameters : 'result t -> Db_type.packed_value list
  val projection : 'result t -> 'result Projection.t
  val shape : 'result t -> Shape.t
  val sql : 'result t -> string
end

module Compiled_command : sig
  type t = Compiled_command.t

  val dialect : t -> Dialect.t
  val template : t -> Template.t
  val parameters : t -> Db_type.packed_value list
  val shape : t -> Shape.t
  val sql : t -> string
end

module Affected_rows = Affected_rows
module Compiler = Compiler
