open! Base
module Db_type = Typed_sql_private.Db_type
module Template = Typed_sql_private.Template
module Shape = Typed_sql_private.Shape

let public_dialect = function
  | Typed_sql_private.Dialect.Postgresql -> Typed_sql.Dialect.Postgresql
  | Typed_sql_private.Dialect.Sqlite -> Typed_sql.Dialect.Sqlite
;;

let private_dialect = function
  | Typed_sql.Dialect.Postgresql -> Typed_sql_private.Dialect.Postgresql
  | Typed_sql.Dialect.Sqlite -> Typed_sql_private.Dialect.Sqlite
;;

module Projection = struct
  type 'a t = 'a Typed_sql_private.Projection.erased

  module Make (A : sig
      include Applicative.S

      val field : 'a Db_type.t -> 'a t
    end) =
  Typed_sql_private.Projection.Make (struct
      include A

      let expr expression = field (Typed_sql_private.Expr.db_type expression)
    end)
end

module Compiled_query = struct
  type 'a t = 'a Typed_sql_private.Compiled_query.t

  let dialect query = Typed_sql_private.Compiled_query.dialect query |> public_dialect
  let sql = Typed_sql_private.Compiled_query.sql
  let template = Typed_sql_private.Compiled_query.template
  let parameters = Typed_sql_private.Compiled_query.parameters
  let projection = Typed_sql_private.Compiled_query.projection
  let shape = Typed_sql_private.Compiled_query.shape
end

module Compiled_command = struct
  type t = Typed_sql_private.Compiled_command.t

  let dialect command =
    Typed_sql_private.Compiled_command.dialect command |> public_dialect
  ;;

  let sql = Typed_sql_private.Compiled_command.sql
  let template = Typed_sql_private.Compiled_command.template
  let parameters = Typed_sql_private.Compiled_command.parameters
  let shape = Typed_sql_private.Compiled_command.shape
end

module Statement = struct
  let public_identifier identifier =
    Typed_sql_private.Identifier.to_string identifier
    |> Typed_sql.Identifier.of_string_exn
  ;;

  let public_compile_error
    : Typed_sql_private.Compile_error.t -> Typed_sql.Compile_error.t
    =
    let module P = Typed_sql_private.Compile_error in
    let open Typed_sql.Compile_error in
    function
    | P.Empty_projection -> Empty_projection
    | P.Foreign_source { visible; actual } -> Foreign_source { visible; actual }
    | P.Negative_limit value -> Negative_limit value
    | P.Negative_offset value -> Negative_offset value
    | P.Empty_assignments kind -> Empty_assignments kind
    | P.Empty_insert_row row -> Empty_insert_row row
    | P.Duplicate_assignment column -> Duplicate_assignment (public_identifier column)
    | P.Mismatched_insert_columns { row; expected; actual } ->
      Mismatched_insert_columns
        { row
        ; expected = List.map expected ~f:public_identifier
        ; actual = List.map actual ~f:public_identifier
        }
    | P.Empty_conflict_target -> Empty_conflict_target
    | P.Duplicate_conflict_target column ->
      Duplicate_conflict_target (public_identifier column)
    | P.Invalid_conflict_target_source { expected; actual } ->
      Invalid_conflict_target_source { expected; actual }
    | P.Empty_conflict_update -> Empty_conflict_update
    | P.Invalid_assignment_source { expected; actual } ->
      Invalid_assignment_source { expected; actual }
    | P.Unsupported_operation { operation; dialect } ->
      Unsupported_operation { operation; dialect = public_dialect dialect }
    | P.Aggregate_not_allowed clause -> Aggregate_not_allowed clause
    | P.Nested_aggregate -> Nested_aggregate
    | P.Ungrouped_expression -> Ungrouped_expression
    | P.Scalar_subquery_may_return_many_rows -> Scalar_subquery_may_return_many_rows
    | P.Invalid_relation_column position -> Invalid_relation_column position
    | P.Duplicate_relation_column column ->
      Duplicate_relation_column (public_identifier column)
    | P.Mismatched_relation_projection { expected; actual } ->
      Mismatched_relation_projection { expected; actual }
    | P.Mismatched_set_projection { expected; actual } ->
      Mismatched_set_projection { expected; actual }
    | P.Unknown_cte id -> Unknown_cte id
    | P.Invalid_recursive_reference id -> Invalid_recursive_reference id
  ;;

  type ('row, 'output) cardinality =
    | Many : ('row, 'row list) cardinality
    | One : ('row, 'row) cardinality
    | Optional : ('row, 'row option) cardinality

  type 'output execution =
    | Query_execution :
        { cardinality : ('row, 'output) cardinality
        ; compiled : 'row Compiled_query.t
        }
        -> 'output execution
    | Command_execution : Compiled_command.t -> Typed_sql.Affected_rows.t execution

  type resolve_error =
    | Dialect_mismatch
    | Binding of Typed_sql.Statement.binding_error
    | Compilation of Typed_sql.Statement.definition_error

  let public_cardinality
    : type row output.
      (row, output) Typed_sql_private.Statement.cardinality -> (row, output) cardinality
    = function
    | Typed_sql_private.Statement.Many -> Many
    | Typed_sql_private.Statement.One -> One
    | Typed_sql_private.Statement.Optional -> Optional
  ;;

  let public_binding_error (error : Typed_sql_private.Statement.binding_error)
    : Typed_sql.Statement.binding_error
    =
    { name = error.name; message = error.message }
  ;;

  let resolve
    : type input output requirements.
      dialect:Typed_sql.Dialect.t
      -> input
      -> (input, output, requirements) Typed_sql.Statement.t
      -> (output execution, resolve_error) Result.t
    =
    fun ~dialect input statement ->
    match
      Typed_sql_private.Statement.resolve
        ~dialect:(private_dialect dialect)
        input
        statement
    with
    | Error (Typed_sql_private.Statement.Compilation { dialect; error }) ->
      Error
        (Compilation
           { dialect = public_dialect dialect; error = public_compile_error error })
    | Error Typed_sql_private.Statement.Dialect_mismatch -> Error Dialect_mismatch
    | Error (Typed_sql_private.Statement.Binding error) ->
      Error (Binding (public_binding_error error))
    | Ok (Typed_sql_private.Statement.Query_execution { cardinality; compiled }) ->
      Ok (Query_execution { cardinality = public_cardinality cardinality; compiled })
    | Ok (Typed_sql_private.Statement.Command_execution compiled) ->
      Ok (Command_execution compiled)
  ;;
end
