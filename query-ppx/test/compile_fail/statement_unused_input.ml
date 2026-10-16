open! Base

let statement = [%pgsql.statement fun (_input : int) -> "SELECT 1::int4 AS id"]
