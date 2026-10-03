open! Base

type t =
  | Postgresql
  | Sqlite

type portable = []
type postgresql = [ `Not_sqlite ]
type sqlite = [ `Not_postgres ]

type both =
  [ `Postgresql
  | `Sqlite
  ]

type ('excluded, 'supports) supports =
  | Portable : (portable, both) supports
  | Concrete_postgresql : (postgresql, [ `Postgresql ]) supports
  | Concrete_sqlite : (sqlite, [ `Sqlite ]) supports

let portable = Portable
let postgresql = Concrete_postgresql
let sqlite = Concrete_sqlite

module Selected = struct
  type _ t =
    | Postgresql : [> `Postgresql ] t
    | Sqlite : [> `Sqlite ] t

  let postgresql = Postgresql
  let sqlite = Sqlite
end

let selected_dialect : type supports. supports Selected.t -> t = function
  | Selected.Postgresql -> Postgresql
  | Selected.Sqlite -> Sqlite
;;

let to_string = function
  | Postgresql -> "postgresql"
  | Sqlite -> "sqlite"
;;
