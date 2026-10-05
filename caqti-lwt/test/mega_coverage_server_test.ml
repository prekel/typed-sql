open! Base
module T = Caqti.Template
module Adapter = Typed_sql_caqti_lwt
module Mega = Typed_sql_mega_coverage_tests.Mega_coverage_test

let ( let* ) = Lwt.bind

let direct sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->. T.Row_type.unit)
    (fun _ -> T.Query.parse sql)
;;

let int64_request sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.int64)
    (fun _ -> T.Query.parse sql)
;;

let string_request sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.string)
    (fun _ -> T.Query.parse sql)
;;

let bool_request sql =
  T.Request.create
    T.Request.Direct
    T.Request_type.Infix.(T.Row_type.unit -->! T.Row_type.bool)
    (fun _ -> T.Query.parse sql)
;;

let or_fail promise =
  let* result = promise in
  Caqti_lwt.or_fail result
;;

let adapter_or_fail promise =
  let* result = promise in
  match result with
  | Ok value -> Lwt.return value
  | Error error -> Lwt.fail_with (Adapter.error_to_string error)
;;

let setup_statements =
  [ "CREATE TABLE public.mega_people (id BIGINT PRIMARY KEY, name TEXT NOT NULL, score BIGINT NOT NULL, nickname TEXT, bio TEXT, status TEXT NOT NULL DEFAULT 'new', active BOOLEAN NOT NULL DEFAULT FALSE)"
  ; "INSERT INTO public.mega_people VALUES (1, 'Ada', 10, 'Ada N', NULL, 'old', FALSE)"
  ; "CREATE TABLE mega_cleanup (id BIGINT PRIMARY KEY)"
  ; "INSERT INTO mega_cleanup VALUES (1)"
  ; "CREATE TABLE mega_maintenance (enabled BOOLEAN NOT NULL)"
  ; "INSERT INTO mega_maintenance VALUES (FALSE)"
  ; "CREATE TABLE mega_events (id BIGINT PRIMARY KEY, person_id BIGINT NOT NULL, label TEXT NOT NULL, nullable_label TEXT, value INTEGER NOT NULL, nullable_value INTEGER, float_value DOUBLE PRECISION NOT NULL, nullable_float_value DOUBLE PRECISION, nullable_id BIGINT, numeric_value NUMERIC NOT NULL, nullable_numeric_value NUMERIC, happened_on DATE NOT NULL, external_id UUID NOT NULL, mapped_label TEXT)"
  ; "INSERT INTO mega_events VALUES (10, 1, 'event', 'optional', 2, NULL, 1.5, NULL, 10, 2.5, NULL, '2026-09-30', '550e8400-e29b-41d4-a716-446655440000', 'mapped')"
  ; "CREATE TABLE mega_expired (id BIGINT PRIMARY KEY, person_id BIGINT NOT NULL, label TEXT NOT NULL, score INTEGER NOT NULL)"
  ; "INSERT INTO mega_expired VALUES (201, 1, 'expired', -1)"
  ; "CREATE TABLE mega_archive (id BIGINT PRIMARY KEY, person_id BIGINT NOT NULL, label TEXT NOT NULL, score INTEGER NOT NULL)"
  ; "INSERT INTO mega_archive VALUES (201, 1, 'archived', 10)"
  ; "CREATE TABLE mega_audit (id BIGINT PRIMARY KEY, person_id BIGINT NOT NULL, label TEXT NOT NULL, score INTEGER NOT NULL, UNIQUE (person_id, score))"
  ; "INSERT INTO mega_audit VALUES (201, 1, 'before upsert', -1)"
  ; "CREATE TABLE mega_outbox (id BIGINT PRIMARY KEY, label TEXT NOT NULL)"
  ; "INSERT INTO mega_outbox VALUES (101, 'already queued')"
  ]
;;

let run conn =
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  let* () =
    Lwt_list.iter_s
      (fun sql -> Connection.exec (direct sql) () |> or_fail)
      setup_statements
  in
  let* rows = Adapter.run ~conn Mega.statement ([ 1L ], 20, 1) |> adapter_or_fail in
  let* () =
    match rows with
    | [ ((person_id, name), (has_events, (events, (aggregate_rows, aggregate_value)))) ]
      ->
      let aggregates_nonempty =
        List.exists aggregate_rows ~f:(fun values -> not (List.is_empty values))
      in
      let aggregate_value_is_zero =
        match aggregate_value with
        | Some value -> Int64.equal value 0L
        | None -> false
      in
      if
        not
          (Int64.equal person_id 1L
           && String.equal name "ada!"
           && has_events
           && Int.equal (List.length events) 1
           && aggregates_nonempty
           && aggregate_value_is_zero)
      then
        Lwt.fail_with "mega query returned unexpected nested results"
      else
        Lwt.return_unit
    | _ -> Lwt.fail_with "mega query did not update exactly one person"
  in
  let* score =
    Connection.find (int64_request "SELECT score FROM public.mega_people WHERE id = 1") ()
    |> or_fail
  in
  let* archive_score =
    Connection.find (int64_request "SELECT score FROM mega_archive WHERE id = 201") ()
    |> or_fail
  in
  let* audit_label =
    Connection.find (string_request "SELECT label FROM mega_audit WHERE id = 201") ()
    |> or_fail
  in
  let* audit_score =
    Connection.find (int64_request "SELECT score FROM mega_audit WHERE id = 201") ()
    |> or_fail
  in
  let* outbox_count =
    Connection.find (int64_request "SELECT count(*) FROM mega_outbox") () |> or_fail
  in
  let* cleanup_count =
    Connection.find (int64_request "SELECT count(*) FROM mega_cleanup") () |> or_fail
  in
  let* maintenance_enabled =
    Connection.find (bool_request "SELECT enabled FROM mega_maintenance") () |> or_fail
  in
  if
    not
      (Int64.equal score 19L
       && Int64.equal archive_score 9L
       && String.equal audit_label "expired"
       && Int64.equal audit_score (-1L)
       && Int64.equal outbox_count 2L
       && Int64.equal cleanup_count 0L
       && maintenance_enabled)
  then
    Lwt.fail_with
      (Stdlib.Printf.sprintf
         "mega query nested DML effects: score=%Ld archive_score=%Ld audit_label=%s audit_score=%Ld outbox_count=%Ld cleanup_count=%Ld maintenance_enabled=%b"
         score
         archive_score
         audit_label
         audit_score
         outbox_count
         cleanup_count
         maintenance_enabled)
  else
    Lwt.return_unit
;;

let main () =
  let* conn = Caqti_lwt_unix.connect (Uri.of_string "postgresql://") |> or_fail in
  let module Connection = (val conn : Caqti_lwt.CONNECTION) in
  Lwt.finalize (fun () -> run conn) (fun () -> Connection.disconnect ())
;;

let () = Lwt_main.run (main ())
