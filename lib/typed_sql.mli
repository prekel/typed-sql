open! Base

(** Backend-independent typed relational query DSL. *)

module Identifier = Identifier
module Db_type = Db_type
module Table = Table
module Column = Column

module Table_ref : sig
  type 'row t = 'row Table_ref.t
end

module Condition = Condition
module Expr = Expr
module Projection = Projection
module Query = Query
module Dialect = Dialect
module Template = Template
module Shape = Shape
module Compile_error = Compile_error
module Compiled_query = Compiled_query
module Compiler = Compiler
