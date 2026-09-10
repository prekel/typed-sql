open! Base

type 'result t =
  { dialect : Dialect.t
  ; template : Template.t
  ; parameters : Db_type.packed_value list
  ; projection : 'result Projection.t
  ; shape : Shape.t
  }

let dialect query = query.dialect
let template query = query.template
let parameters query = query.parameters
let projection query = query.projection
let shape query = query.shape
let sql query = Template.to_sql ~dialect:query.dialect query.template

module Private = struct
  let create ~dialect ~template ~parameters ~projection ~shape =
    { dialect; template; parameters; projection; shape }
  ;;
end
