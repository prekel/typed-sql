open! Base
open Typed_sql

type person
type department

let people : person Table.t = Table.v_exn "people"
let departments : department Table.t = people
