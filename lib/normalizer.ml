open! Base

let normalize_condition condition =
  let rec normalize = function
    | Ast.True -> Ast.True
    | Ast.False -> Ast.False
    | Ast.Compare _ as condition -> condition
    | Ast.Is_null _ as condition -> condition
    | Ast.Is_not_null _ as condition -> condition
    | Ast.Not condition ->
      (match normalize condition with
       | Ast.True -> Ast.False
       | Ast.False -> Ast.True
       | Ast.Not nested -> normalize nested
       | condition -> Ast.Not condition)
    | Ast.And conditions -> normalize_and conditions
    | Ast.Or conditions -> normalize_or conditions
  and normalize_and conditions =
    let conditions =
      List.concat_map conditions ~f:(fun condition ->
        match normalize condition with
        | Ast.And nested -> nested
        | condition -> [ condition ])
    in
    if
      List.exists conditions ~f:(function
        | Ast.False -> true
        | _ -> false)
    then
      Ast.False
    else (
      match
        List.filter conditions ~f:(function
          | Ast.True -> false
          | _ -> true)
      with
      | [] -> Ast.True
      | [ condition ] -> condition
      | conditions -> Ast.And conditions)
  and normalize_or conditions =
    let conditions =
      List.concat_map conditions ~f:(fun condition ->
        match normalize condition with
        | Ast.Or nested -> nested
        | condition -> [ condition ])
    in
    if
      List.exists conditions ~f:(function
        | Ast.True -> true
        | _ -> false)
    then
      Ast.True
    else (
      match
        List.filter conditions ~f:(function
          | Ast.False -> false
          | _ -> true)
      with
      | [] -> Ast.False
      | [ condition ] -> condition
      | conditions -> Ast.Or conditions)
  in
  normalize condition
;;

let optional_condition = function
  | None -> None
  | Some value ->
    (match normalize_condition value with
     | Ast.True -> None
     | condition -> Some condition)
;;

let command (command : Ast.command) =
  { command with Ast.where_ = optional_condition command.where_ }
;;

let select (select : Ast.select) =
  { select with
    Ast.where_ = optional_condition select.where_
  ; joins =
      List.map select.joins ~f:(fun (join : Ast.join) ->
        { join with Ast.on = normalize_condition join.on })
  }
;;

let result_query = function
  | Ast.Select query -> Ast.Select (select query)
  | Ast.Returning returning ->
    Ast.Returning { returning with command = command returning.command }
;;
