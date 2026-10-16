open! Base

let command = [%pgsql.command "SELECT 1::int4 AS id"]
