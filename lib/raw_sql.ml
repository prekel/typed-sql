open! Base

module Output = struct
  include Projection

  let field = raw_field
end

module Postgresql = struct
  type +'requirements part = Ast.raw_part

  let unsafe_sql sql = Ast.Raw_text sql

  let bind (type a r) (expected : a Db_type.t) (value : (a, r) Expr.t) : r part =
    Ast.Raw_bind { expected = Db_type.Pack expected; value = Expr.node value }
  ;;

  let make ~top_level_only output parts =
    let projection = output in
    let fields =
      Projection.output_fields projection
      |> List.map ~f:(function
        | Some name, db_type -> name, db_type
        | None, _ -> failwith "raw output invariant: output fields must be named")
    in
    { Ast.parts; fields; top_level_only; ctes = [] }, projection
  ;;

  let select ?(top_level_only = false) ~output parts =
    let raw, projection = make ~top_level_only output parts in
    Result_query.create_select (Ast.Raw_select raw) projection
  ;;

  let returning ~output parts =
    let raw, projection = make ~top_level_only:true output parts in
    Result_query.create_raw_returning raw projection
  ;;

  let command parts =
    Command.raw { Ast.parts; fields = []; top_level_only = true; ctes = [] }
  ;;
end
