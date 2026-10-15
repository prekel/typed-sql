open! Base

(** Frontend tools and offline metadata APIs. Applications use expression
    extensions; none of these modules connect to PostgreSQL. *)
module Codec = Codec

module Sql = Sql
module Statement_plan = Statement_plan
module Query_bind = Query_bind
module Query_cache = Query_cache
module Query_source = Query_source

(** Register one embedded schema for the existing SQL-inference mode. *)
val register_schema : Typed_sql_schema.Schema_ir.t -> unit

(** Register one embedded query cache for the Prepare/Describe mode.
    A driver must contain exactly one metadata registration of either kind. *)
val register_queries : Query_cache.t -> unit
