open! Base

type t =
  | Postgresql
  | Sqlite

type portable = []
type postgresql = [ `Postgresql ]
type sqlite = [ `Sqlite ]

type 'requirements witness =
  | Portable : portable witness
  | Concrete : t -> 'requirements witness

let portable = Portable
let postgresql : postgresql witness = Concrete Postgresql
let sqlite : sqlite witness = Concrete Sqlite

let to_string = function
  | Postgresql -> "postgresql"
  | Sqlite -> "sqlite"
;;
