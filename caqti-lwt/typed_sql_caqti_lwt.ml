open! Base
module T = Caqti.Template

type error =
  | Compile of Typed_sql.Compile_error.t
  | Unsupported_dialect of string
  | Caqti of Caqti.Error.t

let error_to_string = function
  | Compile error -> Typed_sql.Compile_error.to_string error
  | Unsupported_dialect dialect -> "unsupported Caqti dialect: " ^ dialect
  | Caqti error -> Caqti.Error.show error
;;

let pp_error formatter error =
  Stdlib.Format.pp_print_string formatter (error_to_string error)
;;

let dialect_of_caqti = function
  | T.Dialect.Pgsql _ -> Ok Typed_sql.Dialect.Postgresql
  | T.Dialect.Sqlite _ -> Ok Typed_sql.Dialect.Sqlite
  | T.Dialect.Mysql _ -> Error (Unsupported_dialect "mysql")
  | T.Dialect.Unknown _ -> Error (Unsupported_dialect "unknown")
  | _ -> Error (Unsupported_dialect "unregistered")
;;

let rec caqti_type : type a. a Typed_sql.Db_type.t -> a T.Row_type.t =
  fun db_type ->
  match Typed_sql.Db_type.view db_type with
  | Bool -> T.Row_type.bool
  | Int -> T.Row_type.int
  | Int64 -> T.Row_type.int64
  | Float -> T.Row_type.float
  | Text -> T.Row_type.string
  | Bytes ->
    T.Row_type.custom
      ~encode:(fun value -> Ok (Stdlib.Bytes.to_string value))
      ~decode:(fun value -> Ok (Stdlib.Bytes.of_string value))
      T.Row_type.octets
  | Option db_type -> T.Row_type.option (caqti_type db_type)
  | Map { repr; encode; decode; _ } -> T.Row_type.custom ~encode ~decode (caqti_type repr)
;;

type packed_parameters =
  | Parameters :
      { row_type : 'parameters T.Row_type.t
      ; value : 'parameters
      }
      -> packed_parameters

let pack_parameters parameters =
  List.fold
    parameters
    ~init:(Parameters { row_type = T.Row_type.unit; value = () })
    ~f:(fun (Parameters packed) (Typed_sql.Db_type.Value (db_type, value)) ->
      Parameters
        { row_type = T.Row_type.t2 packed.row_type (caqti_type db_type)
        ; value = packed.value, value
        })
;;

type 'result projection_row =
  | Projection_row :
      { row_type : 'raw T.Row_type.t
      ; decode : 'raw -> 'result
      }
      -> 'result projection_row

let rec projection_row
  : type result. result Typed_sql.Projection.t -> result projection_row
  =
  fun projection ->
  match Typed_sql.Projection.view projection with
  | Pure value ->
    Projection_row { row_type = T.Row_type.unit; decode = (fun () -> value) }
  | Expr expression ->
    Projection_row
      { row_type = caqti_type (Typed_sql.Expr.db_type expression); decode = Fn.id }
  | Map (function_, projection) ->
    (match projection_row projection with
     | Projection_row row ->
       Projection_row
         { row_type = row.row_type; decode = (fun raw -> function_ (row.decode raw)) })
  | Both (left, right) ->
    (match projection_row left, projection_row right with
     | Projection_row left, Projection_row right ->
       Projection_row
         { row_type = T.Row_type.t2 left.row_type right.row_type
         ; decode =
             (fun (left_raw, right_raw) -> left.decode left_raw, right.decode right_raw)
         })
;;

let caqti_query template =
  Typed_sql.Template.parts template
  |> List.map ~f:(function
    | Typed_sql.Template.Text text -> T.Query.lit text
    | Typed_sql.Template.Param index -> T.Query.param index)
  |> T.Query.concat
;;

let map_caqti_error result =
  Result.map_error result ~f:(fun error -> Caqti (error :> Caqti.Error.t))
;;

let compile dialect query =
  let open Result.Let_syntax in
  let%bind dialect = dialect_of_caqti dialect in
  Typed_sql.Compiler.compile ~dialect query
  |> Result.map_error ~f:(fun error -> Compile error)
;;

let fetch ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql.Compiled_query.parameters compiled) with
     | Parameters parameters ->
       (match projection_row (Typed_sql.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->* row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql.Compiled_query.template compiled))
          in
          Connection.collect_list request parameters.value
          |> Lwt.map (fun result ->
            map_caqti_error result |> Result.map ~f:(List.map ~f:row.decode))))
;;

let fetch_one ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql.Compiled_query.parameters compiled) with
     | Parameters parameters ->
       (match projection_row (Typed_sql.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->! row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql.Compiled_query.template compiled))
          in
          Connection.find request parameters.value
          |> Lwt.map (fun result -> map_caqti_error result |> Result.map ~f:row.decode)))
;;

let fetch_opt ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql.Compiled_query.parameters compiled) with
     | Parameters parameters ->
       (match projection_row (Typed_sql.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->? row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql.Compiled_query.template compiled))
          in
          Connection.find_opt request parameters.value
          |> Lwt.map (fun result ->
            map_caqti_error result |> Result.map ~f:(Option.map ~f:row.decode))))
;;
