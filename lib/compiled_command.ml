open! Base

include (
struct
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

  let create ~dialect ~template ~parameters ~shape =
    { dialect; template; parameters; shape }
  ;;
end :
sig
  type t

  val dialect : t -> Dialect.t
  val template : t -> Template.t
  val parameters : t -> Db_type.packed_value list
  val shape : t -> Shape.t
  val sql : t -> string

  val create
    :  dialect:Dialect.t
    -> template:Template.t
    -> parameters:Db_type.packed_value list
    -> shape:Shape.t
    -> t
end)
