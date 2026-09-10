open! Base

type t =
  { dialect : Dialect.t
  ; template : Template.t
  ; parameters : Db_type.packed_value list
  ; shape : Shape.t
  }

let dialect command = command.dialect
let template command = command.template
let parameters command = command.parameters
let shape command = command.shape
let sql command = Template.to_sql ~dialect:command.dialect command.template

module Private = struct
  let create ~dialect ~template ~parameters ~shape =
    { dialect; template; parameters; shape }
  ;;
end
