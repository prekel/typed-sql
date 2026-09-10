open! Base

val result_query : Lower.result_query -> Template.t * Db_type.packed_value list
val command : Lower.command -> Template.t * Db_type.packed_value list
