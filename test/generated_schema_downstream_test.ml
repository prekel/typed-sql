open! Base
open Typed_sql
module First = Generated_schema.User_profile
module Second = Generated_schema.User_profile_2
module Third = Generated_schema.User_profile_3
module Fourth = Generated_schema.Table
module Fifth = Generated_schema.Typed_sql_codegen_2

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
  }
;;

let () =
  ignore first_row;
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    Query.(from First.table |> select First.projection)
    |> Compiler.compile_portable ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore;
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
