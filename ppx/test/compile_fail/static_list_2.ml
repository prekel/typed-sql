(* expected: list substitutions are deferred; only static SQL shapes are supported *)
open! Base

let query conn ids = [%pgsql conn "SELECT id FROM people WHERE id IN $@?ids"]
