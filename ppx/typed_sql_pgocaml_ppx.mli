open! Base

(** Internal frontend exposed for PPX validation tools; applications use
    expression extensions, not these modules. No database execution occurs. *)
module Codec = Codec

module Sql = Sql
module Statement_plan = Statement_plan

(** Register the schema embedded by [typed-sql-codegen --target pgocaml-ppx].
    Generated schema libraries call this when Dune links them into the PPX
    driver. A driver must register exactly one schema before expanding SQL. *)
val register_schema : Typed_sql_schema.Schema_ir.t -> unit
