(* expected: column must appear in GROUP BY *)
open! Base

let query conn = [%pgsql conn "SELECT name, count(*) FROM join_people GROUP BY id"]
