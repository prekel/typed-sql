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

module Default_pgocaml = PGOCaml_generic.Make (Thread)

module Make (P : PGOCaml_generic.PGOCAML_GENERIC with type 'a monad = 'a Lwt.t) = struct
  module Pgocaml = P

  type constraint_kind =
    | Unique
    | Foreign_key
    | Not_null
    | Check
    | Restrict
    | Exclusion
    | Other

  type error =
    | Compile of Typed_sql.Statement.definition_error
    | Parameter of Typed_sql.Statement.binding_error
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
    | Invalid_cache_capacity of int
    | Prepared_cache_closed
    | Pgocaml of exn

  let error_to_string = function
    | Compile { dialect; error } ->
      "statement compilation failed for "
      ^ Typed_sql.Dialect.to_string dialect
      ^ ": "
      ^ Typed_sql.Compile_error.to_string error
    | Parameter { name; message } ->
      (match name with
       | None -> "statement parameter failed validation: " ^ message
       | Some name -> "statement parameter " ^ name ^ " failed validation: " ^ message)
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
    | Invalid_cache_capacity capacity ->
      "prepared cache capacity must be positive, got " ^ Int.to_string capacity
    | Prepared_cache_closed -> "prepared cache is closed"
    | Pgocaml error -> Exn.to_string error
  ;;

  let pp_error formatter error =
    Stdlib.Format.pp_print_string formatter (error_to_string error)
  ;;

  let protect ~context f =
    try Ok (f ()) with
    | error -> Error (context ^ ": " ^ Exn.to_string error)
  ;;

  let date_to_string value =
    let year, month, day = Ptime.to_date value in
    Stdlib.Printf.sprintf "%04d-%02d-%02d" year month day
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
    | Numeric -> Ok (Some (Typed_sql_backend.Decimal.to_string value))
    | Text -> Ok (Some (Pgocaml.string_of_string value))
    | Bytes -> Ok (Some (Pgocaml.string_of_bytea (Bytes.to_string value)))
    | Date -> Ok (Some (date_to_string value))
    | Timestamp -> Ok (Some (Ptime.to_rfc3339 value))
    | Uuid -> Ok (Some (Pgocaml.string_of_uuid value))
    | Named { repr; _ } -> encode repr value
    | Array { encode; _ } -> Result.map (encode value) ~f:Option.some
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
    | Option db_type, Some value ->
      Result.map (decode db_type (Some value)) ~f:Option.some
    | ( ( Bool
        | Int
        | Int64
        | Float
        | Numeric
        | Text
        | Bytes
        | Date
        | Timestamp
        | Uuid
        | Named _
        | Array _
        | Map _ )
      , None ) -> Error ("unexpected NULL for " ^ Typed_sql_backend.Db_type.name db_type)
    | Bool, Some value -> protect ~context:"bool" (fun () -> Pgocaml.bool_of_string value)
    | Int, Some value -> protect ~context:"int" (fun () -> Pgocaml.int_of_string value)
    | Int64, Some value ->
      protect ~context:"int64" (fun () -> Pgocaml.int64_of_string value)
    | Float, Some value ->
      protect ~context:"float" (fun () -> Pgocaml.float_of_string value)
    | Numeric, Some value ->
      (match Typed_sql_backend.Decimal.of_string value with
       | Some decimal -> Ok decimal
       | None -> Error ("numeric: invalid value " ^ value))
    | Text, Some value -> Ok value
    | Bytes, Some value ->
      protect ~context:"bytes" (fun () ->
        Pgocaml.bytea_of_string value |> Bytes.of_string)
    | Date, Some value ->
      (match Typed_sql.Date.of_string value with
       | Some value -> Ok (Typed_sql.Date.to_ptime value)
       | None -> Error ("date: invalid ISO 8601 value " ^ value))
    | Timestamp, Some value ->
      (match Ptime.of_rfc3339 value with
       | Ok (value, _, _) -> Ok value
       | Error _ -> Error ("timestamp: invalid RFC 3339 value " ^ value))
    | Uuid, Some value ->
      (match Typed_sql.Uuid.of_string (Pgocaml.uuid_of_string value) with
       | Some uuid -> Ok (Typed_sql.Uuid.to_string uuid)
       | None -> Error ("uuid: invalid value " ^ value))
    | Named { repr; _ }, Some value -> decode repr (Some value)
    | Array { decode; _ }, Some value -> decode value
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
      | Numeric -> 1700
      | Date -> 1082
      | Timestamp -> 1184
      | Uuid -> 2950
      | Named _ | Array _ -> 0
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

  module Prepared_cache_internal = struct
    type entry =
      { key : string
      ; name : string
      }

    type 'connection t =
      { conn : 'connection Pgocaml.t
      ; capacity : int
      ; id : int
      ; mutable next_name : int
      ; mutable entries : entry list
      ; mutable closed : bool
      ; mutex : Lwt_mutex.t
      }

    let next_id = Stdlib.Atomic.make 0

    let create ?(capacity = 32) ~conn () =
      if capacity <= 0 then
        Error (Invalid_cache_capacity capacity)
      else
        Ok
          { conn
          ; capacity
          ; id = Stdlib.Atomic.fetch_and_add next_id 1
          ; next_name = 0
          ; entries = []
          ; closed = false
          ; mutex = Lwt_mutex.create ()
          }
    ;;

    let key sql types =
      Int.to_string (String.length sql)
      ^ ":"
      ^ sql
      ^ String.concat ~sep:"," (List.map types ~f:(fun oid -> Int32.to_string oid))
    ;;

    let rec find_and_promote key before = function
      | [] -> None
      | entry :: after when String.equal entry.key key ->
        Some (entry, entry :: List.rev_append before after)
      | entry :: after -> find_and_promote key (entry :: before) after
    ;;

    let evict_lru cache =
      match List.rev cache.entries with
      | [] -> Lwt.return_unit
      | last :: rest ->
        let open Lwt.Syntax in
        let* () = Pgocaml.close_statement cache.conn ~name:last.name () in
        cache.entries <- List.rev rest;
        Lwt.return_unit
    ;;

    let execute cache ~sql ~types ~params =
      Lwt_mutex.with_lock cache.mutex (fun () ->
        if cache.closed then
          Lwt.return (Error Prepared_cache_closed)
        else
          Lwt.catch
            (fun () ->
               let open Lwt.Syntax in
               let key = key sql types in
               let* name =
                 match find_and_promote key [] cache.entries with
                 | Some (entry, entries) ->
                   cache.entries <- entries;
                   Lwt.return entry.name
                 | None ->
                   let* () =
                     if List.length cache.entries >= cache.capacity then
                       evict_lru cache
                     else
                       Lwt.return_unit
                   in
                   let name =
                     Stdlib.Printf.sprintf "typed_sql_%d_%d" cache.id cache.next_name
                   in
                   cache.next_name <- cache.next_name + 1;
                   let* () = Pgocaml.prepare cache.conn ~name ~query:sql ~types () in
                   cache.entries <- { key; name } :: cache.entries;
                   Lwt.return name
               in
               let* rows = Pgocaml.execute cache.conn ~name ~params () in
               Lwt.return (Ok rows))
            (fun exn -> Lwt.return (Error (error_of_exn exn))))
    ;;

    let close cache =
      Lwt_mutex.with_lock cache.mutex (fun () ->
        let rec loop () =
          match cache.entries with
          | [] ->
            cache.closed <- true;
            Lwt.return (Ok ())
          | entry :: rest ->
            Lwt.catch
              (fun () ->
                 let open Lwt.Syntax in
                 let* () = Pgocaml.close_statement cache.conn ~name:entry.name () in
                 cache.entries <- rest;
                 loop ())
              (fun exn -> Lwt.return (Error (error_of_exn exn)))
        in
        loop ())
    ;;
  end

  let run_sql ?prepared_cache ~conn ~sql ~parameters () =
    match encode_parameters parameters with
    | Error message -> Lwt.return (Error (Encode message))
    | Ok params ->
      let types = parameter_oids parameters in
      (match prepared_cache with
       | Some cache -> Prepared_cache_internal.execute cache ~sql ~types ~params
       | None ->
         Lwt.catch
           (fun () ->
              let open Lwt.Syntax in
              let* () = Pgocaml.prepare conn ~query:sql ~types () in
              let* rows = Pgocaml.execute conn ~params () in
              Lwt.return (Ok rows))
           (fun error -> Lwt.return (Error (error_of_exn error))))
  ;;

  let fetch_compiled ?prepared_cache ~conn compiled =
    let open Lwt.Syntax in
    let* rows =
      run_sql
        ?prepared_cache
        ~conn
        ~sql:(Typed_sql_backend.Compiled_query.sql compiled)
        ~parameters:(Typed_sql_backend.Compiled_query.parameters compiled)
        ()
    in
    match rows with
    | Error error -> Lwt.return (Error error)
    | Ok rows ->
      Typed_sql_backend.Compiled_query.projection compiled |> fun projection ->
      Result.all (List.map rows ~f:(decode_row projection))
      |> Result.map_error ~f:(fun message -> Decode message)
      |> Lwt.return
  ;;

  let execute_compiled ?prepared_cache ~conn compiled =
    let open Lwt.Syntax in
    let* rows =
      run_sql
        ?prepared_cache
        ~conn
        ~sql:(Typed_sql_backend.Compiled_command.sql compiled)
        ~parameters:(Typed_sql_backend.Compiled_command.parameters compiled)
        ()
    in
    match rows with
    | Error error -> Lwt.return (Error error)
    | Ok [] -> Lwt.return (Ok Typed_sql.Affected_rows.Unknown)
    | Ok rows ->
      Lwt.return (Error (Cardinality { expected = "zero"; actual = List.length rows }))
  ;;

  let apply_cardinality
    : type row output.
      (row, output) Typed_sql_backend.Statement.cardinality
      -> row list
      -> (output, error) Result.t
    =
    fun cardinality rows ->
    match cardinality with
    | Many -> Ok rows
    | One ->
      (match rows with
       | [ row ] -> Ok row
       | rows ->
         Error (Cardinality { expected = "exactly one"; actual = List.length rows }))
    | Optional ->
      (match rows with
       | [] -> Ok None
       | [ row ] -> Ok (Some row)
       | rows ->
         Error (Cardinality { expected = "at most one"; actual = List.length rows }))
  ;;

  let run_with_cache
    : type input output requirements connection.
      ?prepared_cache:connection Prepared_cache_internal.t
      -> conn:connection Pgocaml.t
      -> (input, output, requirements) Typed_sql.Statement.t
      -> input
      -> (output, error) Result.t Lwt.t
    =
    fun ?prepared_cache ~conn statement input ->
    match
      Typed_sql_backend.Statement.resolve
        ~dialect:Typed_sql.Dialect.Postgresql
        input
        statement
    with
    | Error Typed_sql_backend.Statement.Dialect_mismatch ->
      Lwt.return
        (Error
           (Parameter { name = None; message = "statement does not support PostgreSQL" }))
    | Error (Typed_sql_backend.Statement.Binding error) ->
      Lwt.return (Error (Parameter error))
    | Error (Typed_sql_backend.Statement.Compilation error) ->
      Lwt.return (Error (Compile error))
    | Ok (Typed_sql_backend.Statement.Query_execution { cardinality; compiled }) ->
      let open Lwt.Syntax in
      let* result = fetch_compiled ?prepared_cache ~conn compiled in
      (match result with
       | Error error -> Lwt.return (Error error)
       | Ok rows -> Lwt.return (apply_cardinality cardinality rows))
    | Ok (Typed_sql_backend.Statement.Command_execution compiled) ->
      execute_compiled ?prepared_cache ~conn compiled
  ;;

  let run ~conn statement input = run_with_cache ~conn statement input

  module Prepared_cache = struct
    include Prepared_cache_internal

    let run cache statement input =
      run_with_cache ~prepared_cache:cache ~conn:cache.conn statement input
    ;;
  end

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
end

include Make (Default_pgocaml)
