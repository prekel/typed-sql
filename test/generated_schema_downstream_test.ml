open! Base
open Typed_sql
module First = Generated_schema.User_profile
module Second = Generated_schema.User_profile_2
module Third = Generated_schema.User_profile_3

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
  }
;;

let () =
  ignore first_row;
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    Query.(from First.table |> select First.projection)
    |> Compiler.compile ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore;
    Query.(from Second.table |> select Second.projection)
    |> Compiler.compile ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore;
    Query.(from Third.table |> select Third.projection)
    |> Compiler.compile ~dialect
    |> Result.map_error ~f:Compile_error.to_string
    |> Result.ok_or_failwith
    |> ignore)
;;
