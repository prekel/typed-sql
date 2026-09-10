open! Base
module Db_type = Typed_sql_private.Db_type
module Template = Typed_sql_private.Template
module Shape = Typed_sql_private.Shape

module Projection = struct
  type 'a t = 'a Typed_sql_private.Projection.t

  module Make (A : sig
      include Applicative.S

      val field : 'a Db_type.t -> 'a t
    end) =
  Typed_sql_private.Projection.Make (struct
      include A

      let expr expression = field (Typed_sql_private.Expr.db_type expression)
    end)
end

module Compiled_query = Typed_sql_private.Compiled_query
module Compiled_command = Typed_sql_private.Compiled_command
