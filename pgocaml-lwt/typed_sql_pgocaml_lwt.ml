open! Base

module Thread = struct
  type 'a t = 'a Lwt.t

  include Monad.Make (struct
      type nonrec 'a t = 'a t

      let return = Lwt.return
      let bind t ~f = Lwt.bind t f
      let map = `Custom (fun t ~f -> Lwt.map f t)
    end)

  let fail = Lwt.fail
  let catch = Lwt.catch

  type in_channel = Lwt_io.input_channel
  type out_channel = Lwt_io.output_channel

  let open_connection address = Lwt_io.open_connection address
  let output_char = Lwt_io.write_char
  let output_binary_int = Lwt_io.BE.write_int
  let output_string = Lwt_io.write
  let flush = Lwt_io.flush
  let input_char = Lwt_io.read_char
  let input_binary_int = Lwt_io.BE.read_int
  let really_input = Lwt_io.read_into_exactly
  let close_in (channel : in_channel) = Lwt_io.close channel
end

module Pgocaml = PGOCaml_generic.Make (Thread)

type constraint_kind =
  | Unique
  | Foreign_key
  | Not_null
  | Check
  | Restrict
  | Exclusion
  | Other

type error =
  | Compile of Typed_sql.Compile_error.t
  | Encode of string
  | Decode of string
  | Cardinality of
      { expected : string
      ; actual : int
      }
  | Constraint_violation of
      { kind : constraint_kind
      ; message : string
      }
  | Pgocaml of exn

let error_to_string = function
  | Compile error -> Typed_sql.Compile_error.to_string error
  | Encode message -> "parameter encoding failed: " ^ message
  | Decode message -> "row decoding failed: " ^ message
  | Cardinality { expected; actual } ->
    "expected " ^ expected ^ " row(s), got " ^ Int.to_string actual
  | Constraint_violation { kind; message } ->
    let kind =
      match kind with
      | Unique -> "unique"
      | Foreign_key -> "foreign key"
      | Not_null -> "not null"
      | Check -> "check"
      | Restrict -> "restrict"
      | Exclusion -> "exclusion"
      | Other -> "integrity"
    in
    kind ^ " constraint violation: " ^ message
  | Pgocaml error -> Exn.to_string error
;;

let pp_error formatter error =
  Stdlib.Format.pp_print_string formatter (error_to_string error)
;;

let protect ~context f =
  try Ok (f ()) with
  | error -> Error (context ^ ": " ^ Exn.to_string error)
;;

let error_of_exn = function
  | Pgocaml.PostgreSQL_Error (message, fields) as exn ->
    let kind =
      match List.Assoc.find fields 'C' ~equal:Char.equal with
      | Some "23505" -> Some Unique
      | Some "23503" -> Some Foreign_key
      | Some "23502" -> Some Not_null
      | Some "23514" -> Some Check
      | Some "23001" -> Some Restrict
      | Some "23P01" -> Some Exclusion
      | Some code when String.is_prefix code ~prefix:"23" -> Some Other
      | _ -> None
    in
    (match kind with
     | Some kind -> Constraint_violation { kind; message }
     | None -> Pgocaml exn)
  | exn -> Pgocaml exn
;;

let rec encode
  : type a. a Typed_sql_backend.Db_type.t -> a -> (string option, string) Result.t
  =
  fun db_type value ->
  match Typed_sql_backend.Db_type.view db_type with
  | Bool -> Ok (Some (Pgocaml.string_of_bool value))
  | Int -> Ok (Some (Pgocaml.string_of_int value))
  | Int64 -> Ok (Some (Pgocaml.string_of_int64 value))
  | Float -> Ok (Some (Pgocaml.string_of_float value))
  | Text -> Ok (Some (Pgocaml.string_of_string value))
  | Bytes -> Ok (Some (Pgocaml.string_of_bytea (Bytes.to_string value)))
  | Timestamp -> Ok (Some (Ptime.to_rfc3339 value))
  | Option db_type ->
    (match value with
     | None -> Ok None
     | Some value -> encode db_type value)
  | Map { repr; encode = map; _ } ->
    let open Result.Let_syntax in
    let%bind value = map value in
    encode repr value
;;

let rec decode
  : type a. a Typed_sql_backend.Db_type.t -> string option -> (a, string) Result.t
  =
  fun db_type field ->
  match Typed_sql_backend.Db_type.view db_type, field with
  | Option _, None -> Ok None
  | Option db_type, Some value -> Result.map (decode db_type (Some value)) ~f:Option.some
  | (Bool | Int | Int64 | Float | Text | Bytes | Timestamp | Map _), None ->
    Error ("unexpected NULL for " ^ Typed_sql_backend.Db_type.name db_type)
  | Bool, Some value -> protect ~context:"bool" (fun () -> Pgocaml.bool_of_string value)
  | Int, Some value -> protect ~context:"int" (fun () -> Pgocaml.int_of_string value)
  | Int64, Some value ->
    protect ~context:"int64" (fun () -> Pgocaml.int64_of_string value)
  | Float, Some value ->
    protect ~context:"float" (fun () -> Pgocaml.float_of_string value)
  | Text, Some value -> Ok value
  | Bytes, Some value ->
    protect ~context:"bytes" (fun () -> Pgocaml.bytea_of_string value |> Bytes.of_string)
  | Timestamp, Some value ->
    (match Ptime.of_rfc3339 value with
     | Ok (value, _, _) -> Ok value
     | Error _ -> Error ("timestamp: invalid RFC 3339 value " ^ value))
  | Map { repr; decode = map; _ }, Some value ->
    let open Result.Let_syntax in
    let%bind value = decode repr (Some value) in
    map value
;;

let rec oid : type a. a Typed_sql_backend.Db_type.t -> Pgocaml.oid =
  fun db_type ->
  let value =
    match Typed_sql_backend.Db_type.view db_type with
    | Bool -> 16
    | Bytes -> 17
    | Int64 -> 20
    | Int -> 23
    | Text -> 25
    | Float -> 701
    | Timestamp -> 1184
    | Option db_type -> Int32.to_int_exn (oid db_type)
    | Map { repr; _ } -> Int32.to_int_exn (oid repr)
  in
  Int32.of_int_exn value
;;

let encode_parameters parameters =
  Result.all
    (List.map parameters ~f:(fun (Typed_sql_backend.Db_type.Value (db_type, value)) ->
       encode db_type value))
;;

let parameter_oids parameters =
  List.map parameters ~f:(fun (Typed_sql_backend.Db_type.Value (db_type, _)) ->
    oid db_type)
;;

module Projection_decoder = Typed_sql_backend.Projection.Make (struct
    type 'a t = Pgocaml.row -> ('a * Pgocaml.row, string) Result.t

    include Applicative.Make_using_map2 (struct
        type nonrec 'a t = 'a t

        let return value fields = Ok (value, fields)

        let map decode ~f fields =
          Result.map (decode fields) ~f:(fun (value, fields) -> f value, fields)
        ;;

        let map2 left right ~f fields =
          let open Result.Let_syntax in
          let%bind left, fields = left fields in
          let%map right, fields = right fields in
          f left right, fields
        ;;

        let map = `Custom map
      end)

    let field db_type fields =
      match fields with
      | [] -> Error "row has fewer columns than the projection"
      | field :: fields ->
        Result.map (decode db_type field) ~f:(fun value -> value, fields)
    ;;
  end)

let decode_projection = Projection_decoder.run

let decode_row projection row =
  let open Result.Let_syntax in
  let%bind value, remaining = decode_projection projection row in
  if List.is_empty remaining then
    Ok value
  else
    Error ("row has " ^ Int.to_string (List.length remaining) ^ " unexpected column(s)")
;;

let run ~conn ~sql ~parameters =
  match encode_parameters parameters with
  | Error message -> Lwt.return (Error (Encode message))
  | Ok params ->
    Lwt.catch
      (fun () ->
         let open Lwt.Syntax in
         let* () =
           Pgocaml.prepare conn ~query:sql ~types:(parameter_oids parameters) ()
         in
         let* rows = Pgocaml.execute conn ~params () in
         Lwt.return (Ok rows))
      (fun error -> Lwt.return (Error (error_of_exn error)))
;;

let fetch ~conn query =
  match Typed_sql.Compiler.compile ~dialect:Typed_sql.Dialect.Postgresql query with
  | Error error -> Lwt.return (Error (Compile error))
  | Ok compiled ->
    let open Lwt.Syntax in
    let* rows =
      run
        ~conn
        ~sql:(Typed_sql.Compiled_query.sql compiled)
        ~parameters:(Typed_sql_backend.Compiled_query.parameters compiled)
    in
    (match rows with
     | Error error -> Lwt.return (Error error)
     | Ok rows ->
       Typed_sql_backend.Compiled_query.projection compiled |> fun projection ->
       Result.all (List.map rows ~f:(decode_row projection))
       |> Result.map_error ~f:(fun message -> Decode message)
       |> Lwt.return)
;;

let fetch_one ~conn query =
  let open Lwt.Syntax in
  let* result = fetch ~conn query in
  match result with
  | Error error -> Lwt.return (Error error)
  | Ok [ row ] -> Lwt.return (Ok row)
  | Ok rows ->
    Lwt.return
      (Error (Cardinality { expected = "exactly one"; actual = List.length rows }))
;;

let fetch_opt ~conn query =
  let open Lwt.Syntax in
  let* result = fetch ~conn query in
  match result with
  | Error error -> Lwt.return (Error error)
  | Ok [] -> Lwt.return (Ok None)
  | Ok [ row ] -> Lwt.return (Ok (Some row))
  | Ok rows ->
    Lwt.return
      (Error (Cardinality { expected = "at most one"; actual = List.length rows }))
;;

let execute ~conn command =
  match
    Typed_sql.Compiler.compile_command ~dialect:Typed_sql.Dialect.Postgresql command
  with
  | Error error -> Lwt.return (Error (Compile error))
  | Ok compiled ->
    let open Lwt.Syntax in
    let* rows =
      run
        ~conn
        ~sql:(Typed_sql.Compiled_command.sql compiled)
        ~parameters:(Typed_sql_backend.Compiled_command.parameters compiled)
    in
    (match rows with
     | Error error -> Lwt.return (Error error)
     | Ok [] -> Lwt.return (Ok Typed_sql.Affected_rows.Unknown)
     | Ok rows ->
       Lwt.return (Error (Cardinality { expected = "zero"; actual = List.length rows })))
;;

let transaction ~conn ~f =
  let open Lwt.Syntax in
  Lwt.catch
    (fun () ->
       let* () = Pgocaml.begin_work conn in
       Lwt.catch
         (fun () ->
            let* result = f conn in
            match result with
            | Ok value ->
              let* () = Pgocaml.commit conn in
              Lwt.return (Ok value)
            | Error error ->
              let* () = Pgocaml.rollback conn in
              Lwt.return (Error error))
         (fun exn ->
            let* () = Pgocaml.rollback conn in
            Lwt.fail exn))
    (fun exn -> Lwt.return (Error (error_of_exn exn)))
;;
