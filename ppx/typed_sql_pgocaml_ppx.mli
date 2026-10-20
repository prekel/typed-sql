open! Base

(** Frontend tools and offline metadata APIs. Applications use expression
    extensions; none of these modules connect to PostgreSQL. *)
module Codec = Codec

(** SQL parsing and source-position diagnostics for offline inference. *)
module Sql = Sql

(** Resolved statement SQL with ordered parameter and result conversion plans. *)
module Statement_plan = Statement_plan

(** Quotation substitution scanning without SQL type inference. *)
module Query_bind = Query_bind

(** Validated Prepare/Describe metadata and offline registration code generation. *)
module Query_cache = Query_cache

(** Quotation collection from OCaml source ASTs without evaluation. *)
module Query_source = Query_source

(** Register one embedded schema for the existing SQL-inference mode. *)
val register_schema : Typed_sql_schema.Schema_ir.t -> unit

(** Register one embedded query cache for the Prepare/Describe mode.
    A driver must contain exactly one metadata registration of either kind. *)
val register_queries : Query_cache.t -> unit
