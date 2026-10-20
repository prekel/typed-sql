open! Base

(** Cache-backed PostgreSQL quotations. [pgsql.query] and [pgsql.command]
    consume bind expressions; [pgsql.statement] and [pgsql.statement.object]
    use [fun input_pattern -> SQL] to declare runtime inputs and compile a
    static statement when the quotation is evaluated. Getters read fresh
    inputs at binding time. Parameterless SQL also accepts a literal payload
    and uses [unit] input. An input pattern requires at least one SQL hole.
    SELECT and RETURNING use list output; commands without RETURNING use affected-row output.
    The object form requires returned rows. *)

(** Validated offline Prepare/Describe metadata used by quotation expansion. *)
module Query_cache = Typed_sql_ppx_cache.Query_cache

(** Register one embedded query cache. Exactly one registration is required
    per driver; no file is read or database contacted during expansion. *)
val register_queries : Query_cache.t -> unit
