open! Base

type 'row t =
  { id : int
  ; table : 'row Table.t
  }

type ('fields, 'nullable_fields, 'requirements) inferred =
  { id : int
  ; relation : ('fields, 'nullable_fields, 'requirements) Derived_table.inferred
  }

type ('handle, +'requirements) definition =
  { cte : Ast.cte
  ; handle : 'handle
  }

type materialization =
  [ `Materialized
  | `Not_materialized
  ]

type recursion =
  [ `Union
  | `Union_all
  ]

let next_id = Atomic.make 0

let materialization = function
  | `Materialized -> Ast.Materialized
  | `Not_materialized -> Ast.Not_materialized
;;

let make_handle relation =
  { id = Atomic.fetch_and_add next_id 1; table = Derived_table.table relation }
;;

let select ?materialization:hint relation =
  let handle = make_handle relation in
  let relation = Derived_table.relation relation in
  { handle
  ; cte =
      { Ast.cte_id = handle.id
      ; columns = relation.columns
      ; column_types = relation.column_types
      ; result_types = relation.result_types
      ; materialization = Option.map hint ~f:materialization
      ; body = Ast.Select_body relation.query
      }
  }
;;

let recursive ~union ~anchor ~step =
  let handle = make_handle anchor in
  let anchor = Derived_table.relation anchor in
  let step = step handle |> Derived_table.relation in
  let union =
    match union with
    | `Union -> Ast.Recursive_union
    | `Union_all -> Ast.Recursive_union_all
  in
  { handle
  ; cte =
      { Ast.cte_id = handle.id
      ; columns = anchor.columns
      ; column_types = anchor.column_types
      ; result_types = anchor.result_types
      ; materialization = None
      ; body = Ast.Recursive_body { union; anchor; step }
      }
  }
;;

let recursive_relation ~union ~anchor ~step =
  let handle = { id = Atomic.fetch_and_add next_id 1; relation = anchor } in
  let anchor = Derived_table.inferred_relation anchor in
  let step = step handle |> Derived_table.inferred_relation in
  let union =
    match union with
    | `Union -> Ast.Recursive_union
    | `Union_all -> Ast.Recursive_union_all
  in
  { handle
  ; cte =
      { Ast.cte_id = handle.id
      ; columns = anchor.columns
      ; column_types = anchor.column_types
      ; result_types = anchor.result_types
      ; materialization = None
      ; body = Ast.Recursive_body { union; anchor; step }
      }
  }
;;

let add_cte_to_result cte result =
  let ast =
    match Result_query.ast result with
    | Ast.Select (Ast.Simple select) ->
      Ast.Select (Ast.Simple { select with ctes = cte :: select.ctes })
    | Ast.Select (Ast.Source_free source_free) ->
      Ast.Select (Ast.Source_free { source_free with ctes = cte :: source_free.ctes })
    | Ast.Select (Ast.Compound compound) ->
      Ast.Select (Ast.Compound { compound with ctes = cte :: compound.ctes })
    | Ast.Returning returning ->
      Ast.Returning
        { returning with
          command = { returning.command with ctes = cte :: returning.command.ctes }
        }
  in
  Result_query.with_ast result ast
;;

let with_result definition ~f = f definition.handle |> add_cte_to_result definition.cte

let with_command definition ~f =
  let command : Ast.command = f definition.handle |> Command.ast in
  Command.create { command with Ast.ctes = definition.cte :: command.ctes }
;;

let id (cte : _ t) = cte.id
let table (cte : _ t) = cte.table
let inferred_id (cte : (_, _, _) inferred) = cte.id

let inferred_reference (_cte : (_, _, _) inferred) =
  Table_ref.create Derived_table.inferred_table
;;

let inferred_fields (cte : (_, _, _) inferred) reference =
  Derived_table.inferred_fields cte.relation reference
;;

let inferred_nullable_fields (cte : (_, _, _) inferred) reference =
  Derived_table.inferred_nullable_fields cte.relation reference
;;

module Postgresql = struct
  let returning ~table ~columns query =
    let handle = { id = Atomic.fetch_and_add next_id 1; table } in
    let reference = Table_ref.create table in
    let columns = columns reference in
    let returning =
      match Result_query.ast query with
      | Ast.Returning returning -> returning
      | Ast.Select _ ->
        Stdlib.failwith
          "typed-sql invariant violated: PostgreSQL returning CTE requires a RETURNING query"
    in
    { handle
    ; cte =
        { Ast.cte_id = handle.id
        ; columns = Projection.expressions columns
        ; column_types = Projection.types columns
        ; result_types = Projection.types (Result_query.projection query)
        ; materialization = None
        ; body = Ast.Returning_body returning
        }
    }
  ;;

  let command command =
    { handle = ()
    ; cte =
        { Ast.cte_id = Atomic.fetch_and_add next_id 1
        ; columns = []
        ; column_types = []
        ; result_types = []
        ; materialization = None
        ; body = Ast.Command_body (Command.ast command)
        }
    }
  ;;
end
