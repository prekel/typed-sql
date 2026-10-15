(* expected: column must appear in GROUP BY or an aggregate *)
open! Base

let query conn = [%pgsql conn "SELECT name FROM group_keys GROUP BY id"]
