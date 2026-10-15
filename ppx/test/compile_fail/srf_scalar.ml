(* expected: unsupported PostgreSQL function: unnest *)
open! Base

let query conn = [%pgsql conn "SELECT unnest(numbers) FROM native_items"]
