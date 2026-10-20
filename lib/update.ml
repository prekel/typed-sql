open! Base

type unscoped
type scoped

type ('row, 'scope, +'requirements) t =
  { reference : 'row Table_ref.t
  ; source : Ast.source
  ; assignments : Ast.assignment list
  ; from : Ast.source list
  ; where_ : Ast.condition option
  }

let table table =
  let reference = Table_ref.create table in
  { reference
  ; source =
      { Ast.source_id = Table_ref.source_id reference
      ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
      }
  ; assignments = []
  ; from = []
  ; where_ = None
  }
;;

let set assignments update =
  { update with
    assignments = update.assignments @ Assignment.ast update.reference assignments
  }
;;

let set_nullable_expr column expression update =
  let assignment =
    { Ast.source_id = Column.source_id_for update.reference column
    ; column = Column.name column
    ; target_type = Db_type.Pack (Column.db_type column)
    ; value = Ast.Expression (Expr.node expression)
    }
  in
  { update with assignments = update.assignments @ [ assignment ] }
;;

let with_target ~f update = f update.reference update

let from table ~f update =
  let reference = Table_ref.create table in
  let source : Ast.source =
    { source_id = Table_ref.source_id reference
    ; kind = Ast.Table { schema = Table.schema table; table = Table.name table }
    }
  in
  f update.reference reference { update with from = update.from @ [ source ] }
;;

let from_source ~table ~source ~f update =
  let reference = Table_ref.create table in
  f update.reference reference { update with from = update.from @ [ source reference ] }
;;

let from_derived relation ~f update =
  from_source
    ~table:(Derived_table.table relation)
    ~source:(fun reference ->
      { Ast.source_id = Table_ref.source_id reference
      ; kind = Ast.Derived (Derived_table.relation relation)
      })
    ~f
    update
;;

let from_relation relation ~f update =
  let reference = Derived_table.inferred_reference relation in
  let source =
    { Ast.source_id = Table_ref.source_id reference
    ; kind = Ast.Derived (Derived_table.inferred_relation relation)
    }
  in
  f
    update.reference
    (Derived_table.inferred_fields relation reference)
    { update with from = update.from @ [ source ] }
;;

let from_cte cte ~f update =
  from_source
    ~table:(Cte.table cte)
    ~source:(fun reference ->
      { Ast.source_id = Table_ref.source_id reference; kind = Ast.Cte (Cte.id cte) })
    ~f
    update
;;

let where make_condition update =
  let condition = make_condition update.reference |> Condition.node in
  let where_ =
    match update.where_ with
    | None -> Some condition
    | Some existing -> Some (Ast.And [ existing; condition ])
  in
  { update with where_ }
;;

let all_rows update = { update with where_ = None }

let ast update =
  { Ast.ctes = []
  ; kind = Ast.Update
  ; source = update.source
  ; assignments = update.assignments
  ; insert_input = None
  ; from = update.from
  ; conflict = None
  ; where_ = update.where_
  }
;;

let command update = Command.create (ast update)

let returning make_projection update =
  let projection = make_projection update.reference in
  Result_query.create_returning
    { Ast.command = ast update; projection = Projection.expressions projection }
    projection
;;
