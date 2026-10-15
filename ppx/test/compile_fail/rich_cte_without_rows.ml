(* expected: CTE without RETURNING *)
open! Base

let query conn = [%pgsql conn "WITH gone AS (DELETE FROM join_people) SELECT * FROM gone"]
