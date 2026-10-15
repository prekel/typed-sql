(* expected: type modifier metadata *)
open! Base

let query conn = [%pgsql conn "SELECT note::varchar FROM people"]
