open! Base

type ('row, +'requirements) t =
  { table : 'row Table.t
  ; ast : Ast.values
  }

module Row = Derived_table.Fields

module Cell = struct
  type +'requirements t = Cell : ('value, 'requirements) Expr.t -> 'requirements t

  let expr expression = Cell expression
end

let table values = values.table

let create ~table ~columns ~first ~rest =
  let reference = Table_ref.create table in
  let columns = columns reference in
  let rows = first :: rest in
  { table
  ; ast =
      { Ast.descriptor_source_id = Table_ref.source_id reference
      ; columns = Projection.expressions columns
      ; rows =
          List.map rows ~f:(fun row ->
            { Ast.expressions = Row.expressions row; types = Row.types row })
      }
  }
;;

let create_dynamic ~table ~columns ~rows =
  let reference = Table_ref.create table in
  let columns = columns reference in
  { table
  ; ast =
      { Ast.descriptor_source_id = Table_ref.source_id reference
      ; columns = Projection.expressions columns
      ; rows =
          List.map rows ~f:(fun cells ->
            let expressions, types =
              List.map cells ~f:(fun (Cell.Cell expression) ->
                Expr.node expression, Db_type.Pack (Expr.db_type expression))
              |> List.unzip
            in
            { Ast.expressions; types })
      }
  }
;;

let source values reference =
  { Ast.source_id = Table_ref.source_id reference; kind = Ast.Values values.ast }
;;
