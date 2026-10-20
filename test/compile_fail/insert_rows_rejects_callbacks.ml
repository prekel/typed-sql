open! Base
open Typed_sql

let target : unit Table.t = Table.v_exn "items"
let invalid = Insert.(rows target [ Fn.id ] |> command)
