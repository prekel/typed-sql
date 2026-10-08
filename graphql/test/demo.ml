open! Base
open Typed_sql
open Infix
module Gql = Typed_sql_graphql

module Post = struct
  type row

  let table : row Table.t = Table.v_exn "posts"
  let id_column = Column.v_exn table "id" Db_type.int
  let title_column = Column.v_exn table "title" Db_type.text
  let author_id_column = Column.v_exn table "author_id" Db_type.int
  let category_id_column = Column.nullable_v_exn table "category_id" Db_type.int
  let id row = Expr.column row id_column
  let title row = Expr.column row title_column
  let author_id row = Expr.column row author_id_column
  let category_id row = Expr.column row category_id_column
end

module Author = struct
  type row

  let table : row Table.t = Table.v_exn "authors"
  let id_column = Column.v_exn table "id" Db_type.int
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let name row = Expr.column row name_column
end

module Category = struct
  type row

  let table : row Table.t = Table.v_exn "categories"
  let id_column = Column.v_exn table "id" Db_type.int
  let name_column = Column.v_exn table "name" Db_type.text
  let id row = Expr.column row id_column
  let nullable_id row = Expr.nullable_column row id_column
  let nullable_name row = Expr.nullable_column row name_column
end

type object_field =
  | Object_id of string
  | Object_name of string

type selected_field =
  | Post_id of string
  | Post_title of string
  | Post_author of string * object_field list
  | Post_category of string * object_field list

type request =
  { root_key : string
  ; fields : selected_field list
  ; min_id : int option
  ; author_name : string option
  ; category_name : string option
  ; order : Query.direction
  ; first : int
  }

type arguments =
  { min_id : int option
  ; author_name : string option
  ; category_name : string option
  ; order : Query.direction
  ; first : int
  }

let parse_arguments arguments =
  let open Result.Let_syntax in
  let initial =
    { min_id = None; author_name = None; category_name = None; order = `Asc; first = 20 }
  in
  let rec loop parsed = function
    | [] -> Ok parsed
    | (name, value) :: rest ->
      let%bind parsed =
        match name with
        | "minId" ->
          let%map min_id = Gql.Value.optional_int value in
          { parsed with min_id }
        | "authorName" ->
          let%map author_name = Gql.Value.optional_string value in
          { parsed with author_name }
        | "categoryName" ->
          let%map category_name = Gql.Value.optional_string value in
          { parsed with category_name }
        | "first" ->
          let%bind first = Gql.Value.optional_int value in
          (match first with
           | Some first when Int.(first >= 0 && first <= 100) -> Ok { parsed with first }
           | _ -> Error "first must be an Int between 0 and 100")
        | "orderBy" ->
          (match Gql.Value.enum value with
           | Ok "ID_ASC" -> Ok { parsed with order = `Asc }
           | Ok "ID_DESC" -> Ok { parsed with order = `Desc }
           | _ -> Error "orderBy must be ID_ASC or ID_DESC")
        | _ -> Error ("unknown posts argument: " ^ name)
      in
      loop parsed rest
  in
  loop initial arguments
;;

let parse_selections selections ~parse =
  if List.is_empty selections then
    Error "a selection set must not be empty"
  else
    List.map selections ~f:parse |> Result.all
;;

let parse_object_field (field : Gql.Field.t) =
  if not (List.is_empty field.arguments) then
    Error ("arguments are not supported on field: " ^ field.name)
  else if not (List.is_empty field.selections) then
    Error ("scalar field cannot have a selection set: " ^ field.name)
  else (
    match
      field.name
    with
    | "id" -> Ok (Object_id field.response_name)
    | "name" -> Ok (Object_name field.response_name)
    | _ -> Error ("unknown object field: " ^ field.name))
;;

let parse_post_field (field : Gql.Field.t) =
  let open Result.Let_syntax in
  let%bind () =
    if List.is_empty field.arguments then
      Ok ()
    else
      Error ("arguments are not supported on field: " ^ field.name)
  in
  match field.name with
  | "id" | "title" ->
    let%bind () =
      if List.is_empty field.selections then
        Ok ()
      else
        Error ("scalar field cannot have a selection set: " ^ field.name)
    in
    if String.equal field.name "id" then
      Ok (Post_id field.response_name)
    else
      Ok (Post_title field.response_name)
  | "author" | "category" ->
    let%map fields = parse_selections field.selections ~parse:parse_object_field in
    if String.equal field.name "author" then
      Post_author (field.response_name, fields)
    else
      Post_category (field.response_name, fields)
  | _ -> Error ("unknown post field: " ^ field.name)
;;

let parse_request ~query ~variables =
  let open Result.Let_syntax in
  let%bind graphql_request = Gql.Request.parse ~query ~variables in
  let root = graphql_request.root in
  let%bind () =
    if String.equal root.name "posts" then
      Ok ()
    else
      Error ("unknown root field: " ^ root.name)
  in
  let%bind arguments = parse_arguments root.arguments in
  let%map fields = parse_selections root.selections ~parse:parse_post_field in
  { root_key = root.response_name
  ; fields
  ; min_id = arguments.min_id
  ; author_name = arguments.author_name
  ; category_name = arguments.category_name
  ; order = arguments.order
  ; first = arguments.first
  }
;;

let parse_request_exn ~query ~variables =
  match parse_request ~query ~variables with
  | Ok request -> request
  | Error error -> failwith error
;;

let response request rows = `Assoc [ "data", `Assoc [ request.root_key, `List rows ] ]

let projected_expression key expression encode =
  Gql.Json_projection.field ~key expression ~encode
;;

let author_projection fields author =
  let field_projection = function
    | Object_id key -> projected_expression key (Author.id author) (fun id -> `Int id)
    | Object_name key ->
      projected_expression key (Author.name author) (fun name -> `String name)
  in
  Gql.Json_projection.object_ (List.map fields ~f:field_projection)
;;

let category_projection fields category =
  let field_projection = function
    | Object_id key ->
      Projection.map
        (Projection.expr (Category.nullable_id category))
        ~f:(fun id -> key, Option.map id ~f:(fun id -> `Int id))
    | Object_name key ->
      Projection.map
        (Projection.expr (Category.nullable_name category))
        ~f:(fun name -> key, Option.map name ~f:(fun name -> `String name))
  in
  Projection.all (List.map fields ~f:field_projection)
  |> Projection.map ~f:(fun fields ->
    (* Every selected category column is non-null before the LEFT JOIN. *)
    if List.for_all fields ~f:(fun (_, value) -> Option.is_none value) then
      `Null
    else
      `Assoc
        (List.map fields ~f:(fun (key, value) ->
           match value with
           | Some value -> key, value
           | None -> failwith "present category has a NULL required field")))
;;

let post_projection fields post author category =
  let field_projection = function
    | Post_id key -> projected_expression key (Post.id post) (fun id -> `Int id)
    | Post_title key ->
      projected_expression key (Post.title post) (fun title -> `String title)
    | Post_author (key, fields) ->
      (match author with
       | Some author ->
         Projection.map (author_projection fields author) ~f:(fun value -> key, value)
       | None -> failwith "author projection requires an author join")
    | Post_category (key, fields) ->
      (match category with
       | Some category ->
         Projection.map (category_projection fields category) ~f:(fun value -> key, value)
       | None -> failwith "category projection requires a category join")
  in
  Gql.Json_projection.object_ (List.map fields ~f:field_projection)
;;

let post_condition (request : request) post =
  match request.min_id with
  | None -> Condition.true_
  | Some min_id -> Post.id post >=$ min_id
;;

let author_condition (request : request) author =
  match request.author_name with
  | None -> Condition.true_
  | Some name -> Author.name author =$ name
;;

let category_condition (request : request) category =
  match request.category_name with
  | None -> Condition.true_
  | Some name -> Category.nullable_name category =$ Some name
;;

let needs_author (request : request) =
  Option.is_some request.author_name
  || List.exists request.fields ~f:(function
    | Post_author _ -> true
    | _ -> false)
;;

let needs_category (request : request) =
  Option.is_some request.category_name
  || List.exists request.fields ~f:(function
    | Post_category _ -> true
    | _ -> false)
;;

let query (request : request) =
  match needs_author request, needs_category request with
  | false, false ->
    Query.(
      from Post.table
      |> where (fun post -> post_condition request post)
      |> order_by Post.id request.order
      |> limit request.first
      |> select (fun post -> post_projection request.fields post None None))
  | true, false ->
    Query.(
      from Post.table
      |> inner_join Author.table ~on:(fun post author ->
        Post.author_id post =. Author.id author)
      |> where (fun (post, author) ->
        post_condition request post &&. author_condition request author)
      |> order_by (fun (post, _) -> Post.id post) request.order
      |> limit request.first
      |> select (fun (post, author) ->
        post_projection request.fields post (Some author) None))
  | false, true ->
    Query.(
      from Post.table
      |> left_join Category.table ~on:(fun post category ->
        Post.category_id post =. Expr.to_nullable (Category.id category))
      |> where (fun (post, category) ->
        post_condition request post &&. category_condition request category)
      |> order_by (fun (post, _) -> Post.id post) request.order
      |> limit request.first
      |> select (fun (post, category) ->
        post_projection request.fields post None (Some category)))
  | true, true ->
    Query.(
      from Post.table
      |> inner_join Author.table ~on:(fun post author ->
        Post.author_id post =. Author.id author)
      |> left_join Category.table ~on:(fun (post, _) category ->
        Post.category_id post =. Expr.to_nullable (Category.id category))
      |> where (fun ((post, author), category) ->
        post_condition request post
        &&. author_condition request author
        &&. category_condition request category)
      |> order_by (fun ((post, _), _) -> Post.id post) request.order
      |> limit request.first
      |> select (fun ((post, author), category) ->
        post_projection request.fields post (Some author) (Some category)))
;;

let statement : (request, Yojson.Safe.t list, Dialect.both) Statement.t =
  Statement.Dynamic.query_many ~dialect:Dialect.portable query
;;

let sql_exn dialect ~query ~variables =
  let request = parse_request_exn ~query ~variables in
  Statement.sql_exn ~dialect ~input:request statement
;;
