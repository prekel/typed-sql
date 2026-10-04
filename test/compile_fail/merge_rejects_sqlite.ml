open! Base
open Typed_sql

let table : unit Table.t = Table.v_exn "items"

let command =
  Merge.(
    into table
    |> using table ~f:(fun _ _ merge ->
      merge |> on Condition.true_ |> when_matched_do_nothing)
    |> command)
;;

let _ = Statement.command ~dialect:Dialect.sqlite command
