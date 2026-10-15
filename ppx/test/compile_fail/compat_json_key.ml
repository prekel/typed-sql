(* expected: invalid JSON extraction key *)
open! Base

let query conn = [%pgsql conn "SELECT document->true FROM people"]
