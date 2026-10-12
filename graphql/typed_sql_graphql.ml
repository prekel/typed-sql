open! Base
module Graphql = Graphql_parser

module Value = struct
  type t = Graphql.const_value

  let optional_int = function
    | `Int value
      when Int64.(of_int value >= -2_147_483_648L && of_int value <= 2_147_483_647L) ->
      Ok (Some value)
    | `Int _ -> Error "Int is outside the signed 32-bit range"
    | `Null -> Ok None
    | _ -> Error "expected Int"
  ;;

  let optional_string = function
    | `String value -> Ok (Some value)
    | `Null -> Ok None
    | _ -> Error "expected String"
  ;;

  let enum = function
    | `Enum value -> Ok value
    | _ -> Error "expected Enum"
  ;;
end

module Field = struct
  type t =
    { name : string
    ; response_name : string
    ; arguments : (string * Value.t) list
    ; selections : t list
    }
end

let rec map_result values ~f =
  let open Result.Let_syntax in
  match values with
  | [] -> Ok []
  | value :: rest ->
    let%bind mapped = f value in
    let%map mapped_rest = map_result rest ~f in
    mapped :: mapped_rest
;;

let unique_names names =
  let rec check seen = function
    | [] -> Ok ()
    | name :: rest ->
      if Set.mem seen name then
        Error ("duplicate name: " ^ name)
      else
        check (Set.add seen name) rest
  in
  check (Set.empty (module String)) names
;;

let check_variable_value (definition : Graphql.variable_definition) value =
  match definition.typ, value with
  | Graphql.NonNullType _, `Null -> Error ("non-null variable is null: " ^ definition.name)
  | (Graphql.NamedType "String" | NonNullType (NamedType "String")), value ->
    Result.map (Value.optional_string value) ~f:(fun _ -> value)
  | (Graphql.NamedType "Int" | NonNullType (NamedType "Int")), value ->
    Result.map (Value.optional_int value) ~f:(fun _ -> value)
  | _ -> Error ("unsupported variable type: " ^ definition.name)
;;

let check_definitions definitions variables =
  let open Result.Let_syntax in
  let%bind () =
    unique_names
      (List.map definitions ~f:(fun (definition : Graphql.variable_definition) ->
         definition.name))
  in
  let%bind () = unique_names (List.map variables ~f:fst) in
  let%bind _ =
    map_result definitions ~f:(fun (definition : Graphql.variable_definition) ->
      let%bind () =
        match definition.typ, definition.default_value with
        | ( ( Graphql.NamedType ("String" | "Int")
            | NonNullType (NamedType ("String" | "Int")) )
          , None ) -> Ok ()
        | _, Some _ -> Error ("variable defaults are not supported: " ^ definition.name)
        | _ -> Error ("unsupported variable type: " ^ definition.name)
      in
      match List.Assoc.find variables definition.name ~equal:String.equal with
      | Some value ->
        let%map _ = check_variable_value definition value in
        ()
      | None ->
        (match definition.typ with
         | Graphql.NonNullType _ -> Error ("missing variable: " ^ definition.name)
         | _ -> Ok ()))
  in
  let%map _ =
    map_result variables ~f:(fun (name, _) ->
      if
        List.exists definitions ~f:(fun (definition : Graphql.variable_definition) ->
          String.equal definition.name name)
      then
        Ok ()
      else
        Error ("undeclared variable: " ^ name))
  in
  ()
;;

let rec resolve_value ~definitions ~variables
  : Graphql.value -> (Value.t option, string) Result.t
  = function
  | `Variable name ->
    let open Result.Let_syntax in
    let%bind definition =
      match
        List.find definitions ~f:(fun (definition : Graphql.variable_definition) ->
          String.equal definition.name name)
      with
      | Some definition -> Ok definition
      | None -> Error ("undeclared variable: " ^ name)
    in
    (match List.Assoc.find variables name ~equal:String.equal with
     | Some value -> Result.map (check_variable_value definition value) ~f:Option.some
     | None -> Ok None)
  | `Null -> Ok (Some `Null)
  | `Int value ->
    Result.map (Value.optional_int (`Int value)) ~f:(fun _ -> Some (`Int value))
  | `Float value -> Ok (Some (`Float value))
  | `String value -> Ok (Some (`String value))
  | `Bool value -> Ok (Some (`Bool value))
  | `Enum value -> Ok (Some (`Enum value))
  | `List values ->
    Result.map
      (map_result values ~f:(resolve_value ~definitions ~variables))
      ~f:(fun values -> Some (`List (List.map values ~f:(Option.value ~default:`Null))))
  | `Assoc fields ->
    let open Result.Let_syntax in
    let%bind () = unique_names (List.map fields ~f:fst) in
    let%map fields =
      map_result fields ~f:(fun (name, value) ->
        let%map value = resolve_value ~definitions ~variables value in
        Option.map value ~f:(fun value -> name, value))
    in
    Some (`Assoc (List.filter_opt fields))
;;

let rec parse_field ~definitions ~variables (field : Graphql.field) =
  let open Result.Let_syntax in
  let%bind () =
    if List.is_empty field.directives then
      Ok ()
    else
      Error "directives are not supported"
  in
  let%bind () = unique_names (List.map field.arguments ~f:fst) in
  let%bind arguments =
    map_result field.arguments ~f:(fun (name, value) ->
      let%map value = resolve_value ~definitions ~variables value in
      Option.map value ~f:(fun value -> name, value))
  in
  let arguments = List.filter_opt arguments in
  let%map selections = parse_selections ~definitions ~variables field.selection_set in
  { Field.name = field.name
  ; response_name = Option.value field.alias ~default:field.name
  ; arguments
  ; selections
  }

and parse_selections ~definitions ~variables selections =
  let open Result.Let_syntax in
  let%bind fields =
    map_result selections ~f:(function
      | Graphql.Field field -> parse_field ~definitions ~variables field
      | FragmentSpread _ | InlineFragment _ -> Error "fragments are not supported")
  in
  let%map () =
    unique_names (List.map fields ~f:(fun (field : Field.t) -> field.response_name))
  in
  fields
;;

module Request = struct
  type t = { root : Field.t }

  let parse ~query ~variables =
    let open Result.Let_syntax in
    let%bind document =
      Graphql.parse query |> Result.map_error ~f:(fun error -> "syntax error: " ^ error)
    in
    let%bind operation =
      match document with
      | [ Graphql.Operation operation ] -> Ok operation
      | _ -> Error "exactly one query operation is required"
    in
    let%bind () =
      match operation.optype with
      | Graphql.Query -> Ok ()
      | Mutation | Subscription -> Error "only query operations are supported"
    in
    let%bind () =
      if List.is_empty operation.directives then
        Ok ()
      else
        Error "directives are not supported"
    in
    let%bind () = check_definitions operation.variable_definitions variables in
    let%map root =
      match operation.selection_set with
      | [ Graphql.Field field ] ->
        parse_field ~definitions:operation.variable_definitions ~variables field
      | _ -> Error "exactly one root field is required"
    in
    { root }
  ;;
end

module Json_projection = struct
  let field ~key expression ~encode =
    Typed_sql.Projection.map (Typed_sql.Projection.expr expression) ~f:(fun value ->
      key, encode value)
  ;;

  let object_ fields =
    Typed_sql.Projection.all fields
    |> Typed_sql.Projection.map ~f:(fun fields -> `Assoc fields)
  ;;
end
