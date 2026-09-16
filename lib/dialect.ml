open! Base

type t =
  | Postgresql
  | Sqlite

type portable = []
type postgresql = [ `Postgresql ]
type sqlite = [ `Sqlite ]
type 'requirements witness = t

let postgresql = Postgresql
let sqlite = Sqlite
let kind witness = witness

let to_string = function
  | Postgresql -> "postgresql"
  | Sqlite -> "sqlite"
;;
