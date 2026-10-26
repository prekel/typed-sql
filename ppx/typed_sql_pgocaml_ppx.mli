open! Base

(** Offline metadata and code generation APIs. Applications use expression
    extensions; none of these modules connect to PostgreSQL. *)
module Codec = Codec

(** Resolved statement SQL with ordered parameter and result conversion plans. *)
module Statement_plan = Statement_plan

(** Quotation substitution scanning and source diagnostics. *)
module Query_bind = Query_bind

(** Validated Prepare/Describe metadata and offline registration code generation. *)
module Query_cache = Query_cache

(** Quotation collection from OCaml source ASTs without evaluation. *)
module Query_source = Query_source

(** Register the sole embedded Prepare/Describe query cache. Multiple
    registrations and missing metadata produce a located quotation diagnostic. *)
val register_queries : Query_cache.t -> unit
