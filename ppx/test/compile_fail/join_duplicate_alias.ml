(* expected: duplicate source name: p *)
open! Base

let query conn = [%pgsql conn "SELECT p.id FROM join_people p JOIN join_links p ON true"]
