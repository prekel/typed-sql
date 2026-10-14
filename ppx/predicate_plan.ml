open! Base
module N = Native_type

type parameter =
  { value : Sql.parameter
  ; codec : Codec.t
  }

let offset = function
  | Sql.Reference value -> value.offset
  | Parameter_value value -> value.start
  | String_literal (_, offset)
  | Number_literal (_, offset)
  | Bool_literal (_, offset)
  | Null_literal offset -> offset
;;

let fail offset message = Error { Sql.offset; message }

let create ~resolve condition =
  let open Result.Let_syntax in
  let known = function
    | Sql.Reference reference ->
      let%bind column = resolve reference in
      N.of_column ~offset:reference.offset column
    | Number_literal (value, _) ->
      let name =
        match Int64.of_string_opt value with
        | None -> "numeric"
        | Some value ->
          if Int64.(value >= -2147483648L && value <= 2147483647L) then
            "int4"
          else
            "int8"
      in
      Ok (N.Scalar name)
    | Bool_literal _ -> Ok (N.Scalar "bool")
    | Parameter_value value ->
      fail value.start "cannot infer parameter type without a SQL context"
    | String_literal (_, pos) | Null_literal pos ->
      fail pos "literal requires a type context"
  in
  let has_type = function
    | Sql.Reference _ | Number_literal _ | Bool_literal _ -> true
    | _ -> false
  in
  let context values =
    match List.find values ~f:has_type with
    | Some value -> known value
    | None ->
      if
        List.exists values ~f:(function
          | Sql.String_literal _ -> true
          | _ -> false)
      then
        Ok (N.Scalar "text")
      else
        fail
          (offset (List.hd_exn values))
          "cannot infer parameter type without a SQL context"
  in
  let common_context values =
    let%bind types = List.filter values ~f:has_type |> List.map ~f:known |> Result.all in
    match types with
    | [] -> context values
    | first :: rest ->
      List.fold rest ~init:(Ok first) ~f:(fun result next ->
        let%bind previous = result in
        match N.common previous next with
        | Some common -> Ok common
        | None ->
          fail (offset (List.hd_exn values)) "incompatible PostgreSQL IN operand types")
  in
  let operand expected value =
    match value with
    | Sql.Parameter_value value -> Ok [ { value; codec = N.codec expected } ]
    | String_literal _ | Null_literal _ -> Ok []
    | _ ->
      let%bind actual = known value in
      if N.compatible expected actual then
        Ok []
      else
        fail (offset value) "incompatible PostgreSQL operand types"
  in
  let comparison ?(common = false) operator values =
    let%bind expected =
      if common then
        common_context values
      else
        context values
    in
    let%bind () =
      if N.comparable expected then
        Ok ()
      else
        fail
          (offset (List.hd_exn values))
          (if
             String.equal operator "="
             || String.equal operator "<>"
             || String.equal operator "!="
           then
             "PostgreSQL json has no equality operator; use jsonb"
           else
             "PostgreSQL json has no ordering operator; use jsonb")
    in
    let%map parameters = List.map values ~f:(operand expected) |> Result.all in
    List.concat parameters
  in
  let rec check = function
    | Sql.And (left, right) | Or (left, right) ->
      let%bind left = check left in
      let%map right = check right in
      left @ right
    | Not value -> check value
    | Boolean value -> operand (N.Scalar "bool") value
    | Compare (operator, left, right) -> comparison operator [ left; right ]
    | Between (value, low, high, _) -> comparison ">=" [ value; low; high ]
    | Is_null (value, _) ->
      (match value with
       | Parameter_value parameter ->
         fail parameter.start "cannot infer parameter type in IS NULL"
       | Reference reference ->
         let%map _ = resolve reference in
         []
       | String_literal _ | Number_literal _ | Bool_literal _ | Null_literal _ -> Ok [])
    | Like (left, right, _, _, escape) ->
      let values = left :: right :: Option.to_list escape in
      List.map values ~f:(fun value ->
        match value with
        | Sql.Reference _ ->
          let%bind actual = known value in
          if N.text actual then
            Ok []
          else
            fail (offset value) "LIKE requires a text operand"
        | Parameter_value parameter ->
          Ok [ { value = parameter; codec = Codec.Scalar "string" } ]
        | String_literal _ | Null_literal _ -> Ok []
        | _ -> fail (offset value) "LIKE requires a text operand")
      |> Result.all
      |> Result.map ~f:List.concat
    | In (left, values, _) -> comparison ~common:true "=" (left :: values)
    | Quantified (operator, left, right, _) ->
      let%bind element =
        if has_type right then (
          let%bind native = known right in
          match native with
          | N.Array element -> Ok element
          | _ -> fail (offset right) "ANY/ALL requires an array operand")
        else
          context [ left ]
      in
      let%bind () =
        if N.comparable element then
          Ok ()
        else
          fail (offset left) "array element type has no comparison operator"
      in
      let%bind left_params = operand element left in
      let%map right_params = operand (N.Array element) right in
      ignore (operator : string);
      left_params @ right_params
  in
  match condition with
  | None -> Ok []
  | Some condition -> check condition
;;
