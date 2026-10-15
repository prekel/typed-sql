(* expected: column qualifier does not name *)
open! Base

let query conn = [%pgsql conn "SELECT q.id FROM LATERAL (SELECT p.id) q,join_people p"]
