open! Base

type t =
  | Postgresql
  | Sqlite

let to_string = function
  | Postgresql -> "postgresql"
  | Sqlite -> "sqlite"
;;
