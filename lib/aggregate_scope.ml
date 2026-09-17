open! Base

let projection_has_local_aggregate (select : Ast.select) =
  let sources =
    select.source.source_id
    :: List.map select.joins ~f:(fun join -> join.Ast.source.source_id)
  in
  List.exists select.projection ~f:(function
    | Ast.Aggregate Ast.Count_all -> true
    | Ast.Aggregate
        ( Ast.Count (Ast.Column { source_id; _ })
        | Ast.Count_distinct (Ast.Column { source_id; _ }) ) ->
      List.mem sources source_id ~equal:Int.equal
    | Ast.Aggregate (Ast.Count _ | Ast.Count_distinct _) -> true
    | _ -> false)
;;

let at_most_one (select : Ast.select) =
  Option.exists select.limit ~f:(function
    | Ast.Literal limit -> Int.(limit >= 0 && limit <= 1)
    | Ast.Parameter _ -> false)
  || (List.is_empty select.group_by && projection_has_local_aggregate select)
;;
