(* expected: recursive term type differs *)
open! Base

let query conn =
  [%pgsql
    conn
      "WITH RECURSIVE t(n) AS (SELECT 1 UNION ALL SELECT n::bigint FROM t) SELECT n FROM t"]
;;
