open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"

let _ =
  Merge.(
    into table
    |> using table ~f:(fun _ _ merge ->
      merge |> when_matched_do_nothing |> on Condition.true_)
    |> command)
;;
