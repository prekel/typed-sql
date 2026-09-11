open! Base
module T = Caqti.Template

type error =
  | Compile of Typed_sql.Compile_error.t
  | Unsupported_dialect of string
  | Codec of string
  | Caqti of Caqti.Error.t

let error_to_string = function
  | Compile error -> Typed_sql.Compile_error.to_string error
  | Unsupported_dialect dialect -> "unsupported Caqti dialect: " ^ dialect
  | Codec message -> "codec failed: " ^ message
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

type 'a caqti_codec =
  | Caqti_codec :
      { row_type : 'repr T.Row_type.t
      ; encode : 'a -> ('repr, string) Result.t
      ; decode : 'repr -> ('a, string) Result.t
      }
      -> 'a caqti_codec

let rec caqti_codec : type a. a Typed_sql_backend.Db_type.t -> a caqti_codec =
  fun db_type ->
  match Typed_sql_backend.Db_type.view db_type with
  | Bool ->
    Caqti_codec
      { row_type = T.Row_type.bool; encode = Result.return; decode = Result.return }
  | Int ->
    Caqti_codec
      { row_type = T.Row_type.int; encode = Result.return; decode = Result.return }
  | Int64 ->
    Caqti_codec
      { row_type = T.Row_type.int64; encode = Result.return; decode = Result.return }
  | Float ->
    Caqti_codec
      { row_type = T.Row_type.float; encode = Result.return; decode = Result.return }
  | Text ->
    Caqti_codec
      { row_type = T.Row_type.string; encode = Result.return; decode = Result.return }
  | Bytes ->
    Caqti_codec
      { row_type = T.Row_type.octets
      ; encode = (fun value -> Ok (Stdlib.Bytes.to_string value))
      ; decode = (fun value -> Ok (Stdlib.Bytes.of_string value))
      }
  | Option db_type ->
    (match caqti_codec db_type with
     | Caqti_codec codec ->
       Caqti_codec
         { row_type = T.Row_type.option codec.row_type
         ; encode =
             (function
               | None -> Ok None
               | Some value -> Result.map (codec.encode value) ~f:Option.some)
         ; decode =
             (function
               | None -> Ok None
               | Some value -> Result.map (codec.decode value) ~f:Option.some)
         })
  | Map { repr; encode; decode; _ } ->
    (match caqti_codec repr with
     | Caqti_codec repr_codec ->
       Caqti_codec
         { row_type = repr_codec.row_type
         ; encode =
             (fun value ->
               let open Result.Let_syntax in
               let%bind repr = encode value in
               repr_codec.encode repr)
         ; decode =
             (fun raw ->
               let open Result.Let_syntax in
               let%bind repr = repr_codec.decode raw in
               decode repr)
         })
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
    ~init:(Ok (Parameters { row_type = T.Row_type.unit; value = () }))
    ~f:(fun result (Typed_sql_backend.Db_type.Value (db_type, value)) ->
      let open Result.Let_syntax in
      let%bind (Parameters packed) = result in
      let (Caqti_codec codec) = caqti_codec db_type in
      let%map value =
        codec.encode value |> Result.map_error ~f:(fun message -> Codec message)
      in
      Parameters
        { row_type = T.Row_type.t2 packed.row_type codec.row_type
        ; value = packed.value, value
        })
;;

type 'result projection_row =
  | Projection_row :
      { row_type : 'raw T.Row_type.t
      ; decode : 'raw -> ('result, error) Result.t
      }
      -> 'result projection_row

module Projection_decoder = Typed_sql_backend.Projection.Make (struct
    type 'a t = 'a projection_row

    include Applicative.Make_using_map2 (struct
        type nonrec 'a t = 'a t

        let return value =
          Projection_row { row_type = T.Row_type.unit; decode = (fun () -> Ok value) }
        ;;

        let map (Projection_row row) ~f =
          Projection_row
            { row_type = row.row_type
            ; decode = (fun raw -> Result.map (row.decode raw) ~f)
            }
        ;;

        let map2 (Projection_row left) (Projection_row right) ~f =
          Projection_row
            { row_type = T.Row_type.t2 left.row_type right.row_type
            ; decode =
                (fun (a, b) ->
                  let open Result.Let_syntax in
                  let%bind a = left.decode a in
                  let%map b = right.decode b in
                  f a b)
            }
        ;;

        let map = `Custom map
      end)

    let field db_type =
      match caqti_codec db_type with
      | Caqti_codec codec ->
        Projection_row
          { row_type = codec.row_type
          ; decode =
              (fun raw ->
                codec.decode raw |> Result.map_error ~f:(fun message -> Codec message))
          }
    ;;
  end)

let projection_row = Projection_decoder.run

let caqti_query template =
  Typed_sql_backend.Template.map template ~text:T.Query.lit ~param:T.Query.param
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

let compile_command dialect command =
  let open Result.Let_syntax in
  let%bind dialect = dialect_of_caqti dialect in
  Typed_sql.Compiler.compile_command ~dialect command
  |> Result.map_error ~f:(fun error -> Compile error)
;;

let fetch ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       (match projection_row (Typed_sql_backend.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->* row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql_backend.Compiled_query.template compiled))
          in
          Connection.collect_list request parameters.value
          |> Lwt.map (fun result ->
            let open Result.Let_syntax in
            let%bind rows = map_caqti_error result in
            Result.all (List.map rows ~f:row.decode))))
;;

let fetch_one ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       (match projection_row (Typed_sql_backend.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->! row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql_backend.Compiled_query.template compiled))
          in
          Connection.find request parameters.value
          |> Lwt.map (fun result ->
            let open Result.Let_syntax in
            let%bind raw = map_caqti_error result in
            row.decode raw)))
;;

let fetch_opt ~conn query =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile Connection.dialect query with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       (match projection_row (Typed_sql_backend.Compiled_query.projection compiled) with
        | Projection_row row ->
          let request_type =
            T.Request_type.Infix.(parameters.row_type -->? row.row_type)
          in
          let request =
            T.Request.create T.Request.Dynamic request_type (fun _ ->
              caqti_query (Typed_sql_backend.Compiled_query.template compiled))
          in
          Connection.find_opt request parameters.value
          |> Lwt.map (fun result ->
            let open Result.Let_syntax in
            let%bind raw = map_caqti_error result in
            match raw with
            | None -> Ok None
            | Some raw -> Result.map (row.decode raw) ~f:Option.some)))
;;

let execute ~conn command =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match compile_command Connection.dialect command with
  | Error error -> Lwt.return (Error error)
  | Ok compiled ->
    (match pack_parameters (Typed_sql_backend.Compiled_command.parameters compiled) with
     | Error error -> Lwt.return (Error error)
     | Ok (Parameters parameters) ->
       let request_type =
         T.Request_type.Infix.(parameters.row_type -->. T.Row_type.unit)
       in
       let request =
         T.Request.create T.Request.Dynamic request_type (fun _ ->
           caqti_query (Typed_sql_backend.Compiled_command.template compiled))
       in
       Connection.exec_with_affected_count request parameters.value
       |> Lwt.map (function
         | Ok count -> Ok (Typed_sql.Affected_rows.Known count)
         | Error `Unsupported -> Ok Typed_sql.Affected_rows.Unknown
         | Error (#Caqti.Error.t as error) -> Error (Caqti error)))
;;
