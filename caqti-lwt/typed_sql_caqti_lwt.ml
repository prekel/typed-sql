open! Base
module T = Caqti.Template

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
  | Unsupported_dialect of string
  | Dialect_mismatch of
      { expected : Typed_sql.Dialect.t
      ; connection : Typed_sql.Dialect.t
      }
  | Parameter of Typed_sql.Statement.binding_error
  | Codec of string
  | Schema of string
  | Constraint_violation of
      { kind : constraint_kind
      ; message : string
      }
  | Caqti of Caqti.Error.t

let error_to_string = function
  | Compile { dialect; error } ->
    "statement compilation failed for "
    ^ Typed_sql.Dialect.to_string dialect
    ^ ": "
    ^ Typed_sql.Compile_error.to_string error
  | Unsupported_dialect dialect -> "unsupported Caqti dialect: " ^ dialect
  | Dialect_mismatch { expected; connection } ->
    "statement requires "
    ^ Typed_sql.Dialect.to_string expected
    ^ " but the connection uses "
    ^ Typed_sql.Dialect.to_string connection
  | Parameter { name; message } ->
    Option.value_map name ~default:"parameter" ~f:(fun name -> "parameter " ^ name)
    ^ " "
    ^ message
  | Codec message -> "codec failed: " ^ message
  | Schema message -> "schema introspection failed: " ^ message
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
  | Caqti error -> Caqti.Error.show error
;;

let pp_error formatter error =
  Stdlib.Format.pp_print_string formatter (error_to_string error)
;;

module Profile = struct
  type operation =
    | Fetch
    | Fetch_one
    | Fetch_opt
    | Execute

  type failure =
    | Encode
    | Database
    | Decode
    | Dialect
    | Cancelled
    | Raised

  type outcome =
    | Succeeded
    | Failed of failure

  type durations =
    { prepare : float option
    ; database : float option
    ; decode : float option
    ; total : float
    }

  type event =
    { name : string option
    ; operation : operation
    ; dialect : Typed_sql.Dialect.t option
    ; fingerprint : string option
    ; parameter_count : int option
    ; row_count : int option
    ; outcome : outcome
    ; durations : durations
    }

  type observer = event -> unit

  let operation_to_string = function
    | Fetch -> "fetch"
    | Fetch_one -> "fetch_one"
    | Fetch_opt -> "fetch_opt"
    | Execute -> "execute"
  ;;

  let operation_tag = function
    | Fetch -> "f"
    | Fetch_one -> "1"
    | Fetch_opt -> "?"
    | Execute -> "x"
  ;;
end

module Profiler = struct
  type entry =
    { name : string option
    ; operation : Profile.operation
    ; fingerprint : string option
    ; parameter_count : int option
    ; calls : int
    ; failures : int
    ; rows : int
    ; prepare_seconds : float
    ; database_seconds : float
    ; decode_seconds : float
    ; total_seconds : float
    ; max_prepare_seconds : float
    ; max_database_seconds : float
    ; max_decode_seconds : float
    ; max_total_seconds : float
    }

  type snapshot =
    { entries : entry list
    ; overflow_calls : int
    ; overflow_seconds : float
    }

  type aggregate =
    { name : string option
    ; operation : Profile.operation
    ; fingerprint : string option
    ; mutable parameter_count : int option
    ; mutable calls : int
    ; mutable failures : int
    ; mutable rows : int
    ; mutable prepare_seconds : float
    ; mutable database_seconds : float
    ; mutable decode_seconds : float
    ; mutable total_seconds : float
    ; mutable max_prepare_seconds : float
    ; mutable max_database_seconds : float
    ; mutable max_decode_seconds : float
    ; mutable max_total_seconds : float
    }

  type t =
    { max_shapes : int
    ; aggregates : aggregate Hashtbl.M(String).t
    ; mutable overflow_calls : int
    ; mutable overflow_seconds : float
    }

  let create ?(max_shapes = 1024) () =
    if max_shapes <= 0 then
      Stdlib.invalid_arg "Profiler.create: max_shapes must be positive";
    { max_shapes
    ; aggregates = Hashtbl.create (module String)
    ; overflow_calls = 0
    ; overflow_seconds = 0.
    }
  ;;

  let option_key = function
    | None -> "-"
    | Some value -> Int.to_string (String.length value) ^ ":" ^ value
  ;;

  let key (event : Profile.event) =
    String.concat
      ~sep:"|"
      [ option_key event.name
      ; Profile.operation_tag event.operation
      ; option_key event.fingerprint
      ]
  ;;

  let seconds = Option.value ~default:0.

  let add event aggregate =
    let durations = event.Profile.durations in
    aggregate.calls <- aggregate.calls + 1;
    aggregate.failures
    <- (aggregate.failures
        +
        match event.outcome with
        | Succeeded -> 0
        | Failed _ -> 1);
    aggregate.rows <- aggregate.rows + Option.value event.row_count ~default:0;
    aggregate.prepare_seconds <- aggregate.prepare_seconds +. seconds durations.prepare;
    aggregate.database_seconds <- aggregate.database_seconds +. seconds durations.database;
    aggregate.decode_seconds <- aggregate.decode_seconds +. seconds durations.decode;
    aggregate.total_seconds <- aggregate.total_seconds +. durations.total;
    aggregate.max_prepare_seconds
    <- Float.max aggregate.max_prepare_seconds (seconds durations.prepare);
    aggregate.max_database_seconds
    <- Float.max aggregate.max_database_seconds (seconds durations.database);
    aggregate.max_decode_seconds
    <- Float.max aggregate.max_decode_seconds (seconds durations.decode);
    aggregate.max_total_seconds <- Float.max aggregate.max_total_seconds durations.total;
    aggregate.parameter_count
    <- Option.first_some aggregate.parameter_count event.parameter_count
  ;;

  let record profiler event =
    let key = key event in
    match Hashtbl.find profiler.aggregates key with
    | Some aggregate -> add event aggregate
    | None when Hashtbl.length profiler.aggregates < profiler.max_shapes ->
      let aggregate =
        { name = event.name
        ; operation = event.operation
        ; fingerprint = event.fingerprint
        ; parameter_count = event.parameter_count
        ; calls = 0
        ; failures = 0
        ; rows = 0
        ; prepare_seconds = 0.
        ; database_seconds = 0.
        ; decode_seconds = 0.
        ; total_seconds = 0.
        ; max_prepare_seconds = 0.
        ; max_database_seconds = 0.
        ; max_decode_seconds = 0.
        ; max_total_seconds = 0.
        }
      in
      add event aggregate;
      Hashtbl.set profiler.aggregates ~key ~data:aggregate
    | None ->
      profiler.overflow_calls <- profiler.overflow_calls + 1;
      profiler.overflow_seconds <- profiler.overflow_seconds +. event.durations.total
  ;;

  let observer profiler event = record profiler event

  let entry (aggregate : aggregate) : entry =
    { name = aggregate.name
    ; operation = aggregate.operation
    ; fingerprint = aggregate.fingerprint
    ; parameter_count = aggregate.parameter_count
    ; calls = aggregate.calls
    ; failures = aggregate.failures
    ; rows = aggregate.rows
    ; prepare_seconds = aggregate.prepare_seconds
    ; database_seconds = aggregate.database_seconds
    ; decode_seconds = aggregate.decode_seconds
    ; total_seconds = aggregate.total_seconds
    ; max_prepare_seconds = aggregate.max_prepare_seconds
    ; max_database_seconds = aggregate.max_database_seconds
    ; max_decode_seconds = aggregate.max_decode_seconds
    ; max_total_seconds = aggregate.max_total_seconds
    }
  ;;

  let local_seconds (entry : entry) = entry.prepare_seconds

  let snapshot ?(limit = 20) profiler =
    if limit < 0 then
      Stdlib.invalid_arg "Profiler.snapshot: limit must be non-negative";
    let entries =
      Hashtbl.data profiler.aggregates
      |> List.map ~f:entry
      |> List.sort ~compare:(fun left right ->
        Float.compare (local_seconds right) (local_seconds left))
      |> Fn.flip List.take limit
    in
    { entries
    ; overflow_calls = profiler.overflow_calls
    ; overflow_seconds = profiler.overflow_seconds
    }
  ;;

  let reset profiler =
    Hashtbl.clear profiler.aggregates;
    profiler.overflow_calls <- 0;
    profiler.overflow_seconds <- 0.
  ;;

  let snapshot_and_reset ?limit profiler =
    let snapshot = snapshot ?limit profiler in
    reset profiler;
    snapshot
  ;;

  let pp formatter snapshot =
    Stdlib.Format.fprintf
      formatter
      "%-24s %-10s %8s %7s %7s %9s %10s %10s %10s %9s %s@."
      "query"
      "operation"
      "calls"
      "errors"
      "params"
      "rows"
      "prepare"
      "database"
      "decode"
      "local%"
      "fingerprint";
    List.iter snapshot.entries ~f:(fun entry ->
      let local = local_seconds entry in
      let local_percent =
        if Float.(entry.total_seconds > 0.) then
          local /. entry.total_seconds *. 100.
        else
          0.
      in
      Stdlib.Format.fprintf
        formatter
        "%-24s %-10s %8d %7d %7s %9d %10.6f %10.6f %10.6f %8.2f%% %s@."
        (Option.value entry.name ~default:"-")
        (Profile.operation_to_string entry.operation)
        entry.calls
        entry.failures
        (Option.value_map entry.parameter_count ~default:"-" ~f:Int.to_string)
        entry.rows
        entry.prepare_seconds
        entry.database_seconds
        entry.decode_seconds
        local_percent
        (Option.value entry.fingerprint ~default:"-"));
    if snapshot.overflow_calls > 0 then
      Stdlib.Format.fprintf
        formatter
        "overflow: %d calls, %.6fs total@."
        snapshot.overflow_calls
        snapshot.overflow_seconds
  ;;
end

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
  | Numeric ->
    Caqti_codec
      { row_type =
          T.Row_type.enum
            ~encode:Typed_sql_backend.Decimal.to_string
            ~decode:(fun value ->
              match Typed_sql_backend.Decimal.of_string value with
              | Some decimal -> Ok decimal
              | None -> Error ("invalid numeric: " ^ value))
            "numeric"
      ; encode = Result.return
      ; decode = Result.return
      }
  | Text ->
    Caqti_codec
      { row_type = T.Row_type.string; encode = Result.return; decode = Result.return }
  | Bytes ->
    Caqti_codec
      { row_type = T.Row_type.octets
      ; encode = (fun value -> Ok (Stdlib.Bytes.to_string value))
      ; decode = (fun value -> Ok (Stdlib.Bytes.of_string value))
      }
  | Date ->
    Caqti_codec
      { row_type = T.Row_type.pdate; encode = Result.return; decode = Result.return }
  | Timestamp ->
    Caqti_codec
      { row_type = T.Row_type.ptime; encode = Result.return; decode = Result.return }
  | Uuid ->
    Caqti_codec
      { row_type =
          T.Row_type.enum
            ~encode:Fn.id
            ~decode:(fun value ->
              match Typed_sql.Uuid.of_string value with
              | Some uuid -> Ok (Typed_sql.Uuid.to_string uuid)
              | None -> Error ("invalid UUID: " ^ value))
            "uuid"
      ; encode = Result.return
      ; decode = Result.return
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

let classify_caqti_error (error : Caqti.Error.t) =
  let constraint_kind = function
    | `Unique_violation -> Some Unique
    | `Foreign_key_violation -> Some Foreign_key
    | `Not_null_violation -> Some Not_null
    | `Check_violation -> Some Check
    | `Restrict_violation -> Some Restrict
    | `Exclusion_violation -> Some Exclusion
    | `Integrity_constraint_violation__don't_match -> Some Other
    | _ -> None
  in
  let cause =
    match error with
    | (`Request_failed _ | `Response_failed _) as error -> Some (Caqti.Error.cause error)
    | _ -> None
  in
  match Option.bind cause ~f:constraint_kind with
  | Some kind -> Constraint_violation { kind; message = Caqti.Error.show error }
  | None -> Caqti error
;;

let map_caqti_error result =
  Result.map_error result ~f:(fun error -> classify_caqti_error (error :> Caqti.Error.t))
;;

type trace =
  { observer : Profile.observer
  ; name : string option
  ; operation : Profile.operation
  ; started : float
  ; mutable dialect : Typed_sql.Dialect.t option
  ; mutable fingerprint : string option
  ; mutable parameter_count : int option
  ; mutable prepare_seconds : float option
  ; mutable database_seconds : float option
  ; mutable decode_seconds : float option
  ; mutable finished : bool
  }

let now () = Unix.gettimeofday ()
let elapsed started = Float.max 0. (now () -. started)

let time_sync trace ~set f =
  match trace with
  | None -> f ()
  | Some trace ->
    let started = now () in
    (match f () with
     | value ->
       set trace (Some (elapsed started));
       value
     | exception error ->
       set trace (Some (elapsed started));
       raise error)
;;

let time_lwt trace ~set f =
  match trace with
  | None -> f ()
  | Some trace ->
    let started = now () in
    Lwt.try_bind
      f
      (fun value ->
         set trace (Some (elapsed started));
         Lwt.return value)
      (fun error ->
         set trace (Some (elapsed started));
         Lwt.fail error)
;;

let emit trace ~outcome ~row_count =
  match trace with
  | None -> ()
  | Some trace when trace.finished -> ()
  | Some trace ->
    trace.finished <- true;
    let event : Profile.event =
      { name = trace.name
      ; operation = trace.operation
      ; dialect = trace.dialect
      ; fingerprint = trace.fingerprint
      ; parameter_count = trace.parameter_count
      ; row_count
      ; outcome
      ; durations =
          { prepare = trace.prepare_seconds
          ; database = trace.database_seconds
          ; decode = trace.decode_seconds
          ; total = elapsed trace.started
          }
      }
    in
    (try trace.observer event with
     | _ -> ())
;;

let complete trace ~outcome ~row_count result =
  emit trace ~outcome ~row_count;
  Lwt.return result
;;

let with_trace ?observer ?name operation f =
  match observer with
  | None -> f None
  | Some observer ->
    let trace =
      { observer
      ; name
      ; operation
      ; started = now ()
      ; dialect = None
      ; fingerprint = None
      ; parameter_count = None
      ; prepare_seconds = None
      ; database_seconds = None
      ; decode_seconds = None
      ; finished = false
      }
    in
    Lwt.catch
      (fun () -> f (Some trace))
      (fun error ->
         let failure =
           match error with
           | Lwt.Canceled -> Profile.Cancelled
           | _ -> Profile.Raised
         in
         emit (Some trace) ~outcome:(Failed failure) ~row_count:None;
         Lwt.fail error)
;;

let set_prepare trace value = trace.prepare_seconds <- value
let set_database trace value = trace.database_seconds <- value
let set_decode trace value = trace.decode_seconds <- value

let add_prepare trace value =
  trace.prepare_seconds
  <- Some
       (Option.value trace.prepare_seconds ~default:0. +. Option.value value ~default:0.)
;;

let set_dialect trace dialect =
  Option.iter trace ~f:(fun trace -> trace.dialect <- Some dialect)
;;

let fingerprint shape =
  Typed_sql_backend.Shape.to_string shape |> Stdlib.Digest.string |> Stdlib.Digest.to_hex
;;

let describe_query trace compiled =
  Option.iter trace ~f:(fun trace ->
    trace.dialect <- Some (Typed_sql_backend.Compiled_query.dialect compiled);
    trace.fingerprint
    <- Some (fingerprint (Typed_sql_backend.Compiled_query.shape compiled));
    trace.parameter_count
    <- Some (List.length (Typed_sql_backend.Compiled_query.parameters compiled)))
;;

let describe_command trace compiled =
  Option.iter trace ~f:(fun trace ->
    trace.dialect <- Some (Typed_sql_backend.Compiled_command.dialect compiled);
    trace.fingerprint
    <- Some (fingerprint (Typed_sql_backend.Compiled_command.shape compiled));
    trace.parameter_count
    <- Some (List.length (Typed_sql_backend.Compiled_command.parameters compiled)))
;;

let run_fetch_compiled trace ~conn compiled =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  describe_query trace compiled;
  match
    time_sync trace ~set:set_prepare (fun () ->
      pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled))
  with
  | Error error -> complete trace ~outcome:(Failed Encode) ~row_count:None (Error error)
  | Ok (Parameters parameters) ->
    (match
       time_sync trace ~set:add_prepare (fun () ->
         projection_row (Typed_sql_backend.Compiled_query.projection compiled))
     with
     | Projection_row row ->
       let request_type = T.Request_type.Infix.(parameters.row_type -->* row.row_type) in
       let request =
         time_sync trace ~set:add_prepare (fun () ->
           let query = caqti_query (Typed_sql_backend.Compiled_query.template compiled) in
           T.Request.create T.Request.Dynamic request_type (fun _ -> query))
       in
       let open Lwt.Syntax in
       let* result =
         time_lwt trace ~set:set_database (fun () ->
           Connection.collect_list request parameters.value)
       in
       (match map_caqti_error result with
        | Error error ->
          complete trace ~outcome:(Failed Database) ~row_count:None (Error error)
        | Ok rows ->
          let row_count = List.length rows in
          let result =
            time_sync trace ~set:set_decode (fun () ->
              Result.all (List.map rows ~f:row.decode))
          in
          (match result with
           | Ok rows ->
             complete trace ~outcome:Succeeded ~row_count:(Some row_count) (Ok rows)
           | Error error ->
             complete
               trace
               ~outcome:(Failed Decode)
               ~row_count:(Some row_count)
               (Error error))))
;;

let run_fetch_one_compiled trace ~conn compiled =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  describe_query trace compiled;
  match
    time_sync trace ~set:set_prepare (fun () ->
      pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled))
  with
  | Error error -> complete trace ~outcome:(Failed Encode) ~row_count:None (Error error)
  | Ok (Parameters parameters) ->
    (match
       time_sync trace ~set:add_prepare (fun () ->
         projection_row (Typed_sql_backend.Compiled_query.projection compiled))
     with
     | Projection_row row ->
       let request_type = T.Request_type.Infix.(parameters.row_type -->! row.row_type) in
       let request =
         time_sync trace ~set:add_prepare (fun () ->
           let query = caqti_query (Typed_sql_backend.Compiled_query.template compiled) in
           T.Request.create T.Request.Dynamic request_type (fun _ -> query))
       in
       let open Lwt.Syntax in
       let* result =
         time_lwt trace ~set:set_database (fun () ->
           Connection.find request parameters.value)
       in
       (match map_caqti_error result with
        | Error error ->
          complete trace ~outcome:(Failed Database) ~row_count:None (Error error)
        | Ok raw ->
          let result = time_sync trace ~set:set_decode (fun () -> row.decode raw) in
          (match result with
           | Ok row -> complete trace ~outcome:Succeeded ~row_count:(Some 1) (Ok row)
           | Error error ->
             complete trace ~outcome:(Failed Decode) ~row_count:(Some 1) (Error error))))
;;

let run_fetch_opt_compiled trace ~conn compiled =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  describe_query trace compiled;
  match
    time_sync trace ~set:set_prepare (fun () ->
      pack_parameters (Typed_sql_backend.Compiled_query.parameters compiled))
  with
  | Error error -> complete trace ~outcome:(Failed Encode) ~row_count:None (Error error)
  | Ok (Parameters parameters) ->
    (match
       time_sync trace ~set:add_prepare (fun () ->
         projection_row (Typed_sql_backend.Compiled_query.projection compiled))
     with
     | Projection_row row ->
       let request_type = T.Request_type.Infix.(parameters.row_type -->? row.row_type) in
       let request =
         time_sync trace ~set:add_prepare (fun () ->
           let query = caqti_query (Typed_sql_backend.Compiled_query.template compiled) in
           T.Request.create T.Request.Dynamic request_type (fun _ -> query))
       in
       let open Lwt.Syntax in
       let* result =
         time_lwt trace ~set:set_database (fun () ->
           Connection.find_opt request parameters.value)
       in
       (match map_caqti_error result with
        | Error error ->
          complete trace ~outcome:(Failed Database) ~row_count:None (Error error)
        | Ok None -> complete trace ~outcome:Succeeded ~row_count:(Some 0) (Ok None)
        | Ok (Some raw) ->
          let result = time_sync trace ~set:set_decode (fun () -> row.decode raw) in
          (match result with
           | Ok row ->
             complete trace ~outcome:Succeeded ~row_count:(Some 1) (Ok (Some row))
           | Error error ->
             complete trace ~outcome:(Failed Decode) ~row_count:(Some 1) (Error error))))
;;

let run_execute_compiled trace ~conn compiled =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  describe_command trace compiled;
  match
    time_sync trace ~set:set_prepare (fun () ->
      pack_parameters (Typed_sql_backend.Compiled_command.parameters compiled))
  with
  | Error error -> complete trace ~outcome:(Failed Encode) ~row_count:None (Error error)
  | Ok (Parameters parameters) ->
    let request_type = T.Request_type.Infix.(parameters.row_type -->. T.Row_type.unit) in
    let request =
      time_sync trace ~set:add_prepare (fun () ->
        let query = caqti_query (Typed_sql_backend.Compiled_command.template compiled) in
        T.Request.create T.Request.Dynamic request_type (fun _ -> query))
    in
    let open Lwt.Syntax in
    let* result =
      time_lwt trace ~set:set_database (fun () ->
        Connection.exec_with_affected_count request parameters.value)
    in
    (match result with
     | Ok count ->
       complete
         trace
         ~outcome:Succeeded
         ~row_count:(Some count)
         (Ok (Typed_sql.Affected_rows.Known count))
     | Error `Unsupported ->
       complete
         trace
         ~outcome:Succeeded
         ~row_count:None
         (Ok Typed_sql.Affected_rows.Unknown)
     | Error (#Caqti.Error.t as error) ->
       complete
         trace
         ~outcome:(Failed Database)
         ~row_count:None
         (Error (classify_caqti_error (error :> Caqti.Error.t))))
;;

let run
  : type input output requirements.
    ?observer:Profile.observer
    -> ?name:string
    -> conn:Caqti_lwt.connection
    -> (input, output, requirements) Typed_sql.Statement.t
    -> input
    -> (output, error) Result.t Lwt.t
  =
  fun ?observer ?name ~conn statement input ->
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  match dialect_of_caqti Connection.dialect with
  | Error error -> Lwt.return (Error error)
  | Ok dialect ->
    (match Typed_sql_backend.Statement.resolve ~dialect input statement with
     | Error (Typed_sql_backend.Statement.Compilation error) ->
       Lwt.return (Error (Compile error))
     | Error Typed_sql_backend.Statement.Dialect_mismatch ->
       let expected =
         match dialect with
         | Typed_sql.Dialect.Postgresql -> Typed_sql.Dialect.Sqlite
         | Typed_sql.Dialect.Sqlite -> Typed_sql.Dialect.Postgresql
       in
       Lwt.return (Error (Dialect_mismatch { expected; connection = dialect }))
     | Error (Typed_sql_backend.Statement.Binding error) ->
       Lwt.return (Error (Parameter error))
     | Ok (Typed_sql_backend.Statement.Query_execution { cardinality; compiled }) ->
       (match cardinality with
        | Typed_sql_backend.Statement.Many ->
          with_trace ?observer ?name Fetch (fun trace ->
            run_fetch_compiled trace ~conn compiled)
        | Typed_sql_backend.Statement.One ->
          with_trace ?observer ?name Fetch_one (fun trace ->
            run_fetch_one_compiled trace ~conn compiled)
        | Typed_sql_backend.Statement.Optional ->
          with_trace ?observer ?name Fetch_opt (fun trace ->
            run_fetch_opt_compiled trace ~conn compiled))
     | Ok (Typed_sql_backend.Statement.Command_execution compiled) ->
       with_trace ?observer ?name Execute (fun trace ->
         run_execute_compiled trace ~conn compiled))
;;

let transaction ~conn ~f =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let map_transaction_error result = Lwt.map map_caqti_error result in
  let open Lwt.Syntax in
  let* started = map_transaction_error (Connection.start ()) in
  match started with
  | Error error -> Lwt.return (Error error)
  | Ok () ->
    Lwt.catch
      (fun () ->
         let* result = f conn in
         match result with
         | Ok value ->
           let* committed = map_transaction_error (Connection.commit ()) in
           (match committed with
            | Ok () -> Lwt.return (Ok value)
            | Error error ->
              let* rolled_back = map_transaction_error (Connection.rollback ()) in
              Lwt.return
                (match rolled_back with
                 | Ok () -> Error error
                 | Error rollback_error -> Error rollback_error))
         | Error error ->
           let* rolled_back = map_transaction_error (Connection.rollback ()) in
           (match rolled_back with
            | Ok () -> Lwt.return (Error error)
            | Error rollback_error -> Lwt.return (Error rollback_error)))
      (fun exn ->
         let* _ = Connection.rollback () in
         Lwt.fail exn)
;;

module Schema = struct
  type raw_column =
    string option
    * string
    * string
    * (string * bool * string option * (bool * int option))

  type raw_foreign_key =
    string option
    * string
    * string option
    * (int * string * string option * (string * string option))

  type raw_unique = string option * string * string option * (int * string)

  let column_row_type : raw_column T.Row_type.t =
    T.Row_type.t4
      (T.Row_type.option T.Row_type.string)
      T.Row_type.string
      T.Row_type.string
      (T.Row_type.t4
         T.Row_type.string
         T.Row_type.bool
         (T.Row_type.option T.Row_type.string)
         (T.Row_type.t2 T.Row_type.bool (T.Row_type.option T.Row_type.int)))
  ;;

  let foreign_key_row_type : raw_foreign_key T.Row_type.t =
    T.Row_type.t4
      (T.Row_type.option T.Row_type.string)
      T.Row_type.string
      (T.Row_type.option T.Row_type.string)
      (T.Row_type.t4
         T.Row_type.int
         T.Row_type.string
         (T.Row_type.option T.Row_type.string)
         (T.Row_type.t2 T.Row_type.string (T.Row_type.option T.Row_type.string)))
  ;;

  let unique_row_type : raw_unique T.Row_type.t =
    T.Row_type.t4
      (T.Row_type.option T.Row_type.string)
      T.Row_type.string
      (T.Row_type.option T.Row_type.string)
      (T.Row_type.t2 T.Row_type.int T.Row_type.string)
  ;;

  let request row_type sql =
    T.Request.create
      T.Request.Direct
      T.Request_type.Infix.(T.Row_type.unit -->* row_type)
      (fun _ -> T.Query.parse sql)
  ;;

  let sqlite_columns =
    {|
SELECT NULL,
       m.name,
       x.name,
       x.type,
       x."notnull" = 0
         AND NOT
           (x.pk = 1
            AND upper(x.type) = 'INTEGER'
            AND (SELECT COUNT(*) FROM pragma_index_list(m.name) WHERE origin = 'pk') = 0),
       x.dflt_value,
       x.hidden IN (2, 3),
       CASE WHEN x.pk = 0 THEN NULL ELSE x.pk END
FROM sqlite_schema AS m
JOIN pragma_table_xinfo(m.name) AS x
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, x.cid|}
  ;;

  let sqlite_foreign_keys =
    {|
SELECT NULL,
       m.name,
       CAST(f.id AS TEXT),
       f.seq,
       f."from",
       NULL,
       f."table",
       f."to"
FROM sqlite_schema AS m
JOIN pragma_foreign_key_list(m.name) AS f
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, f.id, f.seq|}
  ;;

  let sqlite_uniques =
    {|
SELECT NULL,
       m.name,
       il.name,
       ii.seqno,
       ii.name
FROM sqlite_schema AS m
JOIN pragma_index_list(m.name) AS il
JOIN pragma_index_info(il.name) AS ii
WHERE m.type = 'table'
  AND m.name NOT LIKE 'sqlite_%'
  AND il."unique" = 1
  AND il.origin <> 'pk'
ORDER BY m.name, il.name, ii.seqno|}
  ;;

  let postgresql_columns =
    {|
SELECT c.table_schema,
       c.table_name,
       c.column_name,
       CASE
         WHEN c.data_type = 'USER-DEFINED' THEN c.udt_schema || '.' || c.udt_name
         WHEN c.data_type = 'ARRAY' THEN c.udt_schema || '.' || c.udt_name || '[]'
         ELSE c.data_type
       END,
       c.is_nullable = 'YES',
       c.column_default,
       c.is_generated = 'ALWAYS' OR c.is_identity = 'YES',
       pk.ordinal_position
FROM information_schema.columns AS c
JOIN information_schema.tables AS tables
  ON tables.table_schema = c.table_schema
 AND tables.table_name = c.table_name
LEFT JOIN (
  SELECT kcu.table_schema,
         kcu.table_name,
         kcu.column_name,
         kcu.ordinal_position
  FROM information_schema.table_constraints AS tc
  JOIN information_schema.key_column_usage AS kcu
    ON kcu.constraint_catalog = tc.constraint_catalog
   AND kcu.constraint_schema = tc.constraint_schema
   AND kcu.constraint_name = tc.constraint_name
  WHERE tc.constraint_type = 'PRIMARY KEY'
) AS pk
  ON pk.table_schema = c.table_schema
 AND pk.table_name = c.table_name
 AND pk.column_name = c.column_name
WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
  AND tables.table_type = 'BASE TABLE'
ORDER BY c.table_schema, c.table_name, c.ordinal_position|}
  ;;

  let postgresql_foreign_keys =
    {|
SELECT tc.table_schema,
       tc.table_name,
       tc.constraint_name,
       kcu.ordinal_position,
       kcu.column_name,
       ukcu.table_schema,
       ukcu.table_name,
       ukcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON kcu.constraint_catalog = tc.constraint_catalog
 AND kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_catalog = tc.constraint_catalog
 AND rc.constraint_schema = tc.constraint_schema
 AND rc.constraint_name = tc.constraint_name
JOIN information_schema.key_column_usage AS ukcu
  ON ukcu.constraint_catalog = rc.unique_constraint_catalog
 AND ukcu.constraint_schema = rc.unique_constraint_schema
 AND ukcu.constraint_name = rc.unique_constraint_name
 AND ukcu.ordinal_position = kcu.position_in_unique_constraint
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position|}
  ;;

  let postgresql_uniques =
    {|
SELECT tc.table_schema,
       tc.table_name,
       tc.constraint_name,
       kcu.ordinal_position,
       kcu.column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON kcu.constraint_catalog = tc.constraint_catalog
 AND kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'UNIQUE'
  AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY tc.table_schema, tc.table_name, tc.constraint_name, kcu.ordinal_position|}
  ;;

  let identifier ~context value =
    Typed_sql.Identifier.of_string value
    |> Result.map_error ~f:(fun error ->
      Schema (context ^ ": " ^ Typed_sql.Identifier.error_to_string error))
  ;;

  let optional_identifier ~context = function
    | None -> Ok None
    | Some value -> Result.map (identifier ~context value) ~f:Option.some
  ;;

  let contains type_name fragment =
    String.is_substring (String.uppercase type_name) ~substring:fragment
  ;;

  let sqlite_db_type type_name =
    let open Typed_sql.Schema_ir in
    if String.is_empty type_name || contains type_name "BLOB" then
      Bytes
    else if contains type_name "BOOL" then
      Bool
    else if contains type_name "TIME" then
      Timestamp
    else if contains type_name "DATE" then
      Date
    else if contains type_name "UUID" then
      Uuid
    else if contains type_name "INT" then
      Int64
    else if
      contains type_name "CHAR" || contains type_name "CLOB" || contains type_name "TEXT"
    then
      Text
    else if
      contains type_name "REAL" || contains type_name "FLOA" || contains type_name "DOUB"
    then
      Float
    else
      Unsupported type_name
  ;;

  let postgresql_db_type type_name =
    let open Typed_sql.Schema_ir in
    match String.lowercase type_name with
    | "boolean" -> Bool
    | "smallint" | "integer" -> Int
    | "bigint" -> Int64
    | "real" | "double precision" -> Float
    | "numeric" | "decimal" -> Numeric
    | "text" | "character" | "character varying" -> Text
    | "bytea" -> Bytes
    | "date" -> Date
    | "timestamp with time zone" -> Timestamp
    | "uuid" -> Uuid
    | unsupported -> Unsupported unsupported
  ;;

  let same_key (left_schema, left_table, left_name) (right_schema, right_table, right_name)
    =
    Option.equal String.equal left_schema right_schema
    && String.equal left_table right_table
    && Option.equal String.equal left_name right_name
  ;;

  let group_adjacent rows ~key =
    List.group rows ~break:(fun left right -> not (same_key (key left) (key right)))
  ;;

  let primary_key_columns columns ~schema ~table =
    List.filter_map
      columns
      ~f:(fun (column_schema, column_table, column, (_, _, _, (_, pk))) ->
        if
          Option.equal String.equal schema column_schema
          && String.equal table column_table
        then
          Option.map pk ~f:(fun position -> position, column)
        else
          None)
    |> List.sort ~compare:(fun (left, _) (right, _) -> Int.compare left right)
    |> List.map ~f:snd
  ;;

  let make_foreign_keys ~primary_key_columns rows =
    group_adjacent rows ~key:(fun (schema, table, name, _) -> schema, table, name)
    |> List.map ~f:(fun group ->
      let _, _, _, (_, _, referenced_schema_name, (referenced_table_name, _)) =
        List.hd_exn group
      in
      let open Result.Let_syntax in
      let%bind columns =
        Result.all
          (List.map group ~f:(fun (_, _, _, (_, column, _, _)) ->
             identifier ~context:"foreign-key column" column))
      in
      let%bind referenced_schema =
        optional_identifier ~context:"referenced schema" referenced_schema_name
      in
      let%bind referenced_table =
        identifier ~context:"referenced table" referenced_table_name
      in
      let referenced_columns =
        List.map group ~f:(fun (_, _, _, (_, _, _, (_, column))) -> column)
      in
      let%bind referenced_columns =
        match List.for_all referenced_columns ~f:Option.is_some with
        | true ->
          Result.all
            (List.map referenced_columns ~f:(fun column ->
               identifier ~context:"referenced column" (Option.value_exn column)))
        | false when List.for_all referenced_columns ~f:Option.is_none ->
          (match
             primary_key_columns
               ~schema:referenced_schema_name
               ~table:referenced_table_name
           with
           | [] ->
             Error
               (Schema
                  ("referenced table " ^ referenced_table_name
                 ^ " has no primary key for an implicit foreign key target"))
           | columns ->
             Result.all
               (List.map columns ~f:(identifier ~context:"referenced primary-key column")))
        | false ->
          Error
            (Schema
               ("foreign key to " ^ referenced_table_name
              ^ " mixes explicit and implicit referenced columns"))
      in
      Ok
        (Typed_sql.Schema_ir.foreign_key
           ~columns
           ?referenced_schema
           ~referenced_table
           ~referenced_columns
           ()))
    |> Result.all
  ;;

  let make_uniques rows =
    group_adjacent rows ~key:(fun (schema, table, name, _) -> schema, table, name)
    |> List.map ~f:(fun group ->
      let _, _, name, _ = List.hd_exn group in
      let open Result.Let_syntax in
      let%bind name = optional_identifier ~context:"unique constraint" name in
      let%map columns =
        Result.all
          (List.map group ~f:(fun (_, _, _, (_, column)) ->
             identifier ~context:"unique column" column))
      in
      Typed_sql.Schema_ir.unique_constraint ?name columns)
    |> Result.all
  ;;

  let belongs_to_table ~schema ~table (row_schema, row_table, _, _) =
    Option.equal String.equal schema row_schema && String.equal table row_table
  ;;

  let make_schema ~db_type columns foreign_keys uniques =
    let open Result.Let_syntax in
    let primary_keys = primary_key_columns columns in
    let column_groups =
      List.group
        columns
        ~break:(fun (left_schema, left_table, _, _) (right_schema, right_table, _, _) ->
          not
            (Option.equal String.equal left_schema right_schema
             && String.equal left_table right_table))
    in
    let%map tables =
      List.map column_groups ~f:(fun group ->
        let schema, table, _, _ = List.hd_exn group in
        let%bind schema = optional_identifier ~context:"table schema" schema in
        let%bind name = identifier ~context:"table name" table in
        let%bind columns =
          Result.all
            (List.map
               group
               ~f:
                 (fun
                   ( _
                   , _
                   , name
                   , (database_type, nullable, default, (generated, primary_key_position))
                   )
                 ->
                 let%map name = identifier ~context:"column name" name in
                 Typed_sql.Schema_ir.column
                   ~name
                   ~db_type:(db_type database_type)
                   ~nullable
                   ?default
                   ~generated
                   ?primary_key_position
                   ()))
        in
        let raw_foreign_keys =
          List.filter
            foreign_keys
            ~f:
              (belongs_to_table
                 ~schema:(Option.map schema ~f:Typed_sql.Identifier.to_string)
                 ~table)
        in
        let raw_uniques =
          List.filter
            uniques
            ~f:
              (belongs_to_table
                 ~schema:(Option.map schema ~f:Typed_sql.Identifier.to_string)
                 ~table)
        in
        let%bind foreign_keys =
          make_foreign_keys ~primary_key_columns:primary_keys raw_foreign_keys
        in
        let%map unique_constraints = make_uniques raw_uniques in
        Typed_sql.Schema_ir.table
          ?schema
          ~name
          ~columns
          ~foreign_keys
          ~unique_constraints
          ())
      |> Result.all
    in
    Typed_sql.Schema_ir.v tables
  ;;

  let introspect_with ~conn ~columns_sql ~foreign_keys_sql ~uniques_sql ~db_type =
    let module Connection = (val conn : Caqti_lwt.CONNECTION) in
    let open Lwt.Syntax in
    let* columns = Connection.collect_list (request column_row_type columns_sql) () in
    match map_caqti_error columns with
    | Error error -> Lwt.return (Error error)
    | Ok columns ->
      let* foreign_keys =
        Connection.collect_list (request foreign_key_row_type foreign_keys_sql) ()
      in
      (match map_caqti_error foreign_keys with
       | Error error -> Lwt.return (Error error)
       | Ok foreign_keys ->
         let* uniques =
           Connection.collect_list (request unique_row_type uniques_sql) ()
         in
         Lwt.return
           (let open Result.Let_syntax in
            let%bind uniques = map_caqti_error uniques in
            make_schema ~db_type columns foreign_keys uniques))
  ;;

  let introspect ~conn =
    let module Connection = (val conn : Caqti_lwt.CONNECTION) in
    match Connection.dialect with
    | T.Dialect.Sqlite _ ->
      introspect_with
        ~conn
        ~columns_sql:sqlite_columns
        ~foreign_keys_sql:sqlite_foreign_keys
        ~uniques_sql:sqlite_uniques
        ~db_type:sqlite_db_type
    | T.Dialect.Pgsql _ ->
      introspect_with
        ~conn
        ~columns_sql:postgresql_columns
        ~foreign_keys_sql:postgresql_foreign_keys
        ~uniques_sql:postgresql_uniques
        ~db_type:postgresql_db_type
    | T.Dialect.Mysql _ -> Lwt.return (Error (Unsupported_dialect "mysql"))
    | T.Dialect.Unknown _ -> Lwt.return (Error (Unsupported_dialect "unknown"))
    | _ -> Lwt.return (Error (Unsupported_dialect "unregistered"))
  ;;
end
