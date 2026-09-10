open! Base

module Thread = struct
  type 'a t = 'a Lwt.t

  let return = Lwt.return
  let ( >>= ) = Lwt.bind
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

type error =
  | Compile of Typed_sql.Compile_error.t
  | Encode of string
  | Decode of string
  | Cardinality of
      { expected : string
      ; actual : int
      }
  | Pgocaml of exn

let error_to_string = function
  | Compile error -> Typed_sql.Compile_error.to_string error
  | Encode message -> "parameter encoding failed: " ^ message
  | Decode message -> "row decoding failed: " ^ message
  | Cardinality { expected; actual } ->
    "expected " ^ expected ^ " row(s), got " ^ Int.to_string actual
  | Pgocaml error -> Exn.to_string error
;;

let pp_error formatter error =
  Stdlib.Format.pp_print_string formatter (error_to_string error)
;;

let protect ~context f =
  try Ok (f ()) with
  | error -> Error (context ^ ": " ^ Exn.to_string error)
;;

let rec encode : type a. a Typed_sql.Db_type.t -> a -> (string option, string) Result.t =
  fun db_type value ->
  match Typed_sql.Db_type.view db_type with
  | Bool -> Ok (Some (Pgocaml.string_of_bool value))
  | Int -> Ok (Some (Pgocaml.string_of_int value))
  | Int64 -> Ok (Some (Pgocaml.string_of_int64 value))
  | Float -> Ok (Some (Pgocaml.string_of_float value))
  | Text -> Ok (Some (Pgocaml.string_of_string value))
  | Bytes -> Ok (Some (Pgocaml.string_of_bytea (Bytes.to_string value)))
  | Option db_type ->
    (match value with
     | None -> Ok None
     | Some value -> encode db_type value)
  | Map { repr; encode = map; _ } ->
    let open Result.Let_syntax in
    let%bind value = map value in
    encode repr value
;;

let rec decode : type a. a Typed_sql.Db_type.t -> string option -> (a, string) Result.t =
  fun db_type field ->
  match Typed_sql.Db_type.view db_type, field with
  | Option _, None -> Ok None
  | Option db_type, Some value -> Result.map (decode db_type (Some value)) ~f:Option.some
  | (Bool | Int | Int64 | Float | Text | Bytes | Map _), None ->
    Error ("unexpected NULL for " ^ Typed_sql.Db_type.name db_type)
  | Bool, Some value -> protect ~context:"bool" (fun () -> Pgocaml.bool_of_string value)
  | Int, Some value -> protect ~context:"int" (fun () -> Pgocaml.int_of_string value)
  | Int64, Some value ->
    protect ~context:"int64" (fun () -> Pgocaml.int64_of_string value)
  | Float, Some value ->
    protect ~context:"float" (fun () -> Pgocaml.float_of_string value)
  | Text, Some value -> Ok value
  | Bytes, Some value ->
    protect ~context:"bytes" (fun () -> Pgocaml.bytea_of_string value |> Bytes.of_string)
  | Map { repr; decode = map; _ }, Some value ->
    let open Result.Let_syntax in
    let%bind value = decode repr (Some value) in
    map value
;;

let rec oid : type a. a Typed_sql.Db_type.t -> Pgocaml.oid =
  fun db_type ->
  let value =
    match Typed_sql.Db_type.view db_type with
    | Bool -> 16
    | Bytes -> 17
    | Int64 -> 20
    | Int -> 23
    | Text -> 25
    | Float -> 701
    | Option db_type -> Int32.to_int_exn (oid db_type)
    | Map { repr; _ } -> Int32.to_int_exn (oid repr)
  in
  Int32.of_int_exn value
;;

let encode_parameters parameters =
  Result.all
    (List.map parameters ~f:(fun (Typed_sql.Db_type.Value (db_type, value)) ->
       encode db_type value))
;;

let parameter_oids parameters =
  List.map parameters ~f:(fun (Typed_sql.Db_type.Value (db_type, _)) -> oid db_type)
;;

let rec decode_projection
  : type result.
    result Typed_sql.Projection.t
    -> Pgocaml.row
    -> (result * Pgocaml.row, string) Result.t
  =
  fun projection fields ->
  match Typed_sql.Projection.view projection with
  | Pure value -> Ok (value, fields)
  | Expr expression ->
    (match fields with
     | [] -> Error "row has fewer columns than the projection"
     | field :: fields ->
       Result.map
         (decode (Typed_sql.Expr.db_type expression) field)
         ~f:(fun value -> value, fields))
  | Map (map, projection) ->
    Result.map (decode_projection projection fields) ~f:(fun (value, fields) ->
      map value, fields)
  | Both (left, right) ->
    let open Result.Let_syntax in
    let%bind left, fields = decode_projection left fields in
    let%map right, fields = decode_projection right fields in
    (left, right), fields
;;

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
      (fun error -> Lwt.return (Error (Pgocaml error)))
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
        ~parameters:(Typed_sql.Compiled_query.parameters compiled)
    in
    (match rows with
     | Error error -> Lwt.return (Error error)
     | Ok rows ->
       Typed_sql.Compiled_query.projection compiled |> fun projection ->
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
        ~parameters:(Typed_sql.Compiled_command.parameters compiled)
    in
    (match rows with
     | Error error -> Lwt.return (Error error)
     | Ok [] -> Lwt.return (Ok Typed_sql.Affected_rows.Unknown)
     | Ok rows ->
       Lwt.return (Error (Cardinality { expected = "zero"; actual = List.length rows })))
;;
