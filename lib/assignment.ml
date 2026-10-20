open! Base

type ('row, +'requirements) t =
  | Omitted
  | Assignment :
      ('row, 'base, 'value) Column.t * Ast.assignment_value
      -> ('row, 'requirements) t

let expr column expression = Assignment (column, Ast.Expression (Expr.node expression))
let ( := ) = expr
let value column value = expr column (Expr.constant (Column.db_type column) value)
let default column = Assignment (column, Ast.Default)

let value_opt column = function
  | None -> Omitted
  | Some value_ -> value column value_
;;

let expr_opt column = function
  | None -> Omitted
  | Some expression -> expr column expression
;;

let ast reference assignments =
  List.filter_map assignments ~f:(function
    | Omitted -> None
    | Assignment (column, value) ->
      Some
        { Ast.source_id = Column.source_id_for reference column
        ; column = Column.name column
        ; target_type = Db_type.Pack (Column.db_type column)
        ; value
        })
;;
