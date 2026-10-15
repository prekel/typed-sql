(* expected: LATERAL reference requires an INNER or LEFT JOIN *)
open! Base

let query conn =
  [%pgsql
    conn
      "SELECT * FROM group_keys k RIGHT JOIN ROWS FROM(generate_series(1,k.id)) q ON true"]
;;
