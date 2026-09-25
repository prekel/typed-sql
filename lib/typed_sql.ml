open! Base
module Identifier = Typed_sql_private.Identifier
module Date = Typed_sql_private.Date
module Uuid = Typed_sql_private.Uuid
module Decimal = Typed_sql_private.Decimal
module Db_type = Typed_sql_private.Db_type
module Schema_ir = Typed_sql_private.Schema_ir
module Schema_snapshot = Typed_sql_private.Schema_snapshot
module Schema_codegen = Typed_sql_private.Schema_codegen
module Table = Typed_sql_private.Table
module Column = Typed_sql_private.Column
module Table_ref = Typed_sql_private.Table_ref
module Nullable_table_ref = Typed_sql_private.Nullable_table_ref
module Condition = Typed_sql_private.Condition
module Expr = Typed_sql_private.Expr
module Scalar_query = Typed_sql_private.Scalar_query
module Pagination_parameter = Typed_sql_private.Pagination_parameter
module Aggregate_order = Typed_sql_private.Aggregate_order

module Infix = struct
  include Expr.Infix
  include Condition.Infix
end

module Projection = Typed_sql_private.Projection
module Aggregate_projection = Typed_sql_private.Aggregate_projection
module Cardinality = Typed_sql_private.Cardinality
module Query = Typed_sql_private.Query
module Result_query = Typed_sql_private.Result_query
module Command = Typed_sql_private.Command
module Derived_table = Typed_sql_private.Derived_table
module Cte = Typed_sql_private.Cte
module Insert = Typed_sql_private.Insert
module Update = Typed_sql_private.Update
module Delete = Typed_sql_private.Delete
module Dialect = Typed_sql_private.Dialect
module Statement = Typed_sql_private.Statement

module Postgresql = struct
  module Numeric = struct
    let sum_int64 = Typed_sql_private.Expr.sum_int64
    let sum_int64_nullable = Typed_sql_private.Expr.sum_int64_nullable
    let sum_numeric = Typed_sql_private.Expr.sum_numeric
    let sum_numeric_nullable = Typed_sql_private.Expr.sum_numeric_nullable
    let min_numeric = Typed_sql_private.Expr.min_numeric
    let max_numeric = Typed_sql_private.Expr.max_numeric
    let min_numeric_nullable = Typed_sql_private.Expr.min_numeric_nullable
    let max_numeric_nullable = Typed_sql_private.Expr.max_numeric_nullable
  end

  module Numeric_projection = struct
    let sum_int64 = Typed_sql_private.Aggregate_projection.sum_int64
    let sum_int64_nullable = Typed_sql_private.Aggregate_projection.sum_int64_nullable
    let sum_numeric = Typed_sql_private.Aggregate_projection.sum_numeric
    let sum_numeric_nullable = Typed_sql_private.Aggregate_projection.sum_numeric_nullable
    let min_numeric = Typed_sql_private.Aggregate_projection.min_numeric
    let max_numeric = Typed_sql_private.Aggregate_projection.max_numeric
    let min_numeric_nullable = Typed_sql_private.Aggregate_projection.min_numeric_nullable
    let max_numeric_nullable = Typed_sql_private.Aggregate_projection.max_numeric_nullable
  end

  module Query = struct
    let having = Typed_sql_private.Query.having
    let intersect_all = Typed_sql_private.Query.intersect_all
    let except_all = Typed_sql_private.Query.except_all
  end

  module Cte = Typed_sql_private.Cte.Postgresql
end

module Compile_error = Typed_sql_private.Compile_error
module Affected_rows = Typed_sql_private.Affected_rows
