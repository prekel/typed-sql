open! Base

include (
struct
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
  let pp formatter query = Template.pp ~dialect:query.dialect formatter query.template

  let create ~dialect ~template ~parameters ~projection ~shape =
    { dialect; template; parameters; projection; shape }
  ;;
end :
sig
  type 'result t

  val dialect : 'result t -> Dialect.t
  val template : 'result t -> Template.t
  val parameters : 'result t -> Db_type.packed_value list
  val projection : 'result t -> 'result Projection.t
  val shape : 'result t -> Shape.t
  val sql : 'result t -> string
  val pp : Formatter.t -> 'result t -> unit

  val create
    :  dialect:Dialect.t
    -> template:Template.t
    -> parameters:Db_type.packed_value list
    -> projection:'result Projection.t
    -> shape:Shape.t
    -> 'result t
end)
