open! Base

type 'row t =
  { schema : Identifier.t option
  ; name : Identifier.t
  }

let v ?schema name = { schema; name }

let v_exn ?schema name =
  let schema = Option.map schema ~f:Identifier.of_string_exn in
  v ?schema (Identifier.of_string_exn name)
;;

let name table = table.name
let schema table = table.schema

let equal left right =
  Identifier.equal left.name right.name
  && Option.equal Identifier.equal left.schema right.schema
;;
