open! Base
open Typed_sql
open Statement_compile
module First = Generated_schema.User_profile_2
module Second = Generated_schema.User_profile
module Third = Generated_schema.User_profile_3
module Fourth = Generated_schema.Table
module Fifth = Generated_schema.Typed_sql_codegen_2
module Advanced = Generated_schema.Advanced
module Generated_types = Generated_schema.Typed_sql_generated_types

let advanced_row : Advanced.t =
  { local_value =
      Local_timestamp.create
        ~date:(Date.of_ymd_exn ~year:2026 ~month:9 ~day:30)
        ~hour:12
        ~minute:30
        ~second:0
        ~microsecond:123_456
      |> Result.ok_or_failwith
  ; float_value = 12.5
  ; duration = Interval.create ~months:13 ~days:2 ~microseconds:3_000_000L
  ; payload = `Assoc [ "value", `Int 1 ]
  ; payload_binary = `Assoc [ "value", `Int 2 ]
  ; mood = Generated_types.Type_public_mood.Happy
  ; result_status = Generated_types.Type_public_result_status.Ok
  ; username = Generated_types.Type_public_username.of_base "Ada"
  ; host =
      Generated_types.Type_public_host.of_base
        (Ipaddr.Prefix.of_string_exn "192.0.2.1/24")
  ; inet_value = Ipaddr.Prefix.of_string_exn "198.51.100.3/24"
  ; small_value = Schema_test_codecs.Small_int.Small 42
  ; numbers =
      Pg_array.create
        ~dimensions:[ 2; 2 ]
        ~lower_bounds:[ 1; 1 ]
        ~elements:[ Some 1; None; Some 3; Some 4 ]
      |> Result.ok_or_failwith
  ; rational_value = Q.of_string "2/3"
  ; geometry_value = 1., 2.
  }
;;

let first_row : First.t =
  { id = 1L
  ; id_column_2 = 7
  ; display_name = "Ada"
  ; display_name_2 = "Lovelace"
  ; display_name_3 = "Countess"
  ; table_2 = true
  ; published_on = Date.of_ymd_exn ~year:2026 ~month:9 ~day:12
  ; created_at = Ptime.epoch
  ; external_id = Uuid.of_string_exn "550e8400-e29b-41d4-a716-446655440000"
  ; reference = "reference"
  ; return_2 = "return"
  ; land_ = "land"
  ; field = "underscore"
  ; map_2 = "map"
  ; total = Decimal.of_string "123.45" |> Option.value_exn
  }
;;

let () =
  ignore first_row;
  ignore advanced_row;
  let module Status = Generated_types.Type_public_result_status in
  (match Status.encode Status.Ok, Status.encode Status.Error with
   | Stdlib.Result.Ok "Ok", Stdlib.Result.Ok "Error" -> ()
   | _ -> failwith "generated enum encode confused enum and result constructors");
  (match Status.decode "Ok", Status.decode "Error", Status.decode "other" with
   | ( Stdlib.Result.Ok Status.Ok
     , Stdlib.Result.Ok Status.Error
     , Stdlib.Result.Error "unknown enum label" ) -> ()
   | _ -> failwith "generated enum decode confused enum and result constructors");
  Query.(from Advanced.table |> select Advanced.projection)
  |> Compiler.compile ~dialect:Dialect.postgresql
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
  |> ignore;
  let sql =
    Insert.(
      into Advanced.table
      |> set_expr
           Advanced.float_value_column
           (Expr.constant Schema_test_codecs.Local_float.db_type 12.5)
      |> command)
    |> Compiler.compile_command ~dialect:Dialect.postgresql
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> Compiled_command.sql
  in
  assert (String.is_substring sql ~substring:"CAST($1 AS \"pg_catalog\".\"timestamp\")");
  Query.(from First.table |> select First.projection)
  |> Compiler.compile ~dialect:Dialect.postgresql
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
  |> ignore;
  (match
     Query.(from First.table |> select First.projection)
     |> Compiler.compile ~dialect:Dialect.sqlite
   with
   | Error _ -> ()
   | Ok _ -> failwith "generated numeric schema unexpectedly compiled for SQLite");
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    Query.(from Second.table |> select Second.projection)
    |> Compiler.compile_portable ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore;
    Query.(from Third.table |> select Third.projection)
    |> Compiler.compile_portable ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore;
    Query.(from Fourth.table |> select Fourth.projection)
    |> Compiler.compile_portable ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore;
    Query.(from Fifth.table |> select Fifth.projection)
    |> Compiler.compile_portable ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore)
;;
