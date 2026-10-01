open! Base

type ('row, +'requirements) t =
  { table : 'row Table.t
  ; relation : Ast.relation
  }

module Fields = struct
  type (_, _, _) t =
    | Field :
        ('value, 'requirements) Expr.t
        -> ( ('value, 'requirements) Expr.t
             , ('value option, 'requirements) Expr.t
             , 'requirements )
             t
    | Both :
        ('left, 'nullable_left, 'requirements) t
        * ('right, 'nullable_right, 'requirements) t
        -> ('left * 'right, 'nullable_left * 'nullable_right, 'requirements) t

  let expr expression = Field expression
  let both left right = Both (left, right)
  let pair left right = Both (Field left, Field right)

  let rec expressions
    : type fields nullable requirements.
      (fields, nullable, requirements) t -> Ast.expr list
    = function
    | Field expression -> [ Expr.node expression ]
    | Both (left, right) -> expressions left @ expressions right
  ;;

  let rec types
    : type fields nullable requirements.
      (fields, nullable, requirements) t -> Db_type.packed list
    = function
    | Field expression -> [ Db_type.Pack (Expr.db_type expression) ]
    | Both (left, right) -> types left @ types right
  ;;

  let name index = Identifier.of_string_exn ("field_" ^ Int.to_string (index + 1))

  let column source_id index db_type =
    { Expr.node =
        Ast.Column { source_id; name = name index; db_type = Db_type.Pack db_type }
    ; db_type
    }
  ;;

  let rec fields_from
    : type fields nullable requirements.
      source_id:int -> int -> (fields, nullable, requirements) t -> fields * int
    =
    fun ~source_id index -> function
    | Field expression -> column source_id index (Expr.db_type expression), index + 1
    | Both (left, right) ->
      let left, index = fields_from ~source_id index left in
      let right, index = fields_from ~source_id index right in
      (left, right), index
  ;;

  let rec nullable_fields_from
    : type fields nullable requirements.
      source_id:int -> int -> (fields, nullable, requirements) t -> nullable * int
    =
    fun ~source_id index -> function
    | Field expression ->
      column source_id index (Db_type.option (Expr.db_type expression)), index + 1
    | Both (left, right) ->
      let left, index = nullable_fields_from ~source_id index left in
      let right, index = nullable_fields_from ~source_id index right in
      (left, right), index
  ;;

  let fields fields ~source_id = fields_from ~source_id 0 fields |> fst
  let nullable_fields fields ~source_id = nullable_fields_from ~source_id 0 fields |> fst

  let columns fields ~source_id =
    types fields
    |> List.mapi ~f:(fun index (Db_type.Pack db_type) ->
      Expr.node (column source_id index db_type))
  ;;
end

type inferred_row

let inferred_table : inferred_row Table.t = Table.v_exn "__typed_sql_relation"

type ('fields, 'nullable_fields, 'requirements) inferred =
  { ast_relation : Ast.relation
  ; fields : int -> 'fields
  ; nullable_fields : int -> 'nullable_fields
  }

let create ~table ~columns query =
  let reference = Table_ref.create table in
  let columns = columns reference in
  let query_ast =
    match Result_query.ast query with
    | Ast.Select query -> query
    | Ast.Returning _ ->
      Stdlib.failwith
        "typed-sql invariant violated: a derived table requires a SELECT query"
  in
  { table
  ; relation =
      { Ast.query = query_ast
      ; columns = Projection.expressions columns
      ; column_types = Projection.types columns
      ; result_types = Projection.types (Result_query.projection query)
      }
  }
;;

let table relation = relation.table
let relation relation = relation.relation

let create_inferred fields query =
  let descriptor_reference = Table_ref.create inferred_table in
  let source_id = Table_ref.source_id descriptor_reference in
  let types = Fields.types fields in
  { ast_relation =
      { Ast.query = Ast.Simple { query with projection = Fields.expressions fields }
      ; columns = Fields.columns fields ~source_id
      ; column_types = types
      ; result_types = types
      }
  ; fields = (fun source_id -> Fields.fields fields ~source_id)
  ; nullable_fields = (fun source_id -> Fields.nullable_fields fields ~source_id)
  }
;;

let create_inferred_one expression =
  let fields = Fields.expr expression in
  let descriptor_reference = Table_ref.create inferred_table in
  let source_id = Table_ref.source_id descriptor_reference in
  let types = Fields.types fields in
  { ast_relation =
      { Ast.query = Ast.Source_free { ctes = []; expression = Expr.node expression }
      ; columns = Fields.columns fields ~source_id
      ; column_types = types
      ; result_types = types
      }
  ; fields = (fun source_id -> Fields.fields fields ~source_id)
  ; nullable_fields = (fun source_id -> Fields.nullable_fields fields ~source_id)
  }
;;

let inferred_reference _relation = Table_ref.create inferred_table
let inferred_relation relation = relation.ast_relation
let inferred_fields relation reference = relation.fields (Table_ref.source_id reference)

let inferred_nullable_fields relation reference =
  relation.nullable_fields (Table_ref.source_id reference)
;;
