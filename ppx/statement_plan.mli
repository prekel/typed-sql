open! Base

type field =
  { name : string
  ; codec : Codec.t
  ; nullable : bool
  }

type parameter =
  { value : Sql.parameter
  ; codec : Codec.t
  }

(** Rows always contains at least one field. Command preserves the PG'OCaml
    unit-result contract for DML without RETURNING. *)
type result =
  | Command
  | Rows of field list

type t =
  { sql : string
  ; result : result
  ; parameters : parameter list
  }

(** Resolve sources and exact codecs. Only returned and parameter columns
    need supported type metadata; unused unsupported columns and DEFAULT writes
    are harmless. JOIN conditions see their operands; LATERAL derived queries
    see preceding sources with PostgreSQL join restrictions. ROWS FROM functions
    share that scope and cannot reference each other's outputs. SELECT SRFs
    preserve a static output shape; disallowed clause/argument contexts fail
    before runtime, while row expansion and NULL padding remain server semantics.
    Unqualified columns must resolve uniquely; aliases hide
    original relation names. Wildcards preserve source and snapshot column order.
    EXCLUDED assignments require identical exact native types. *)
val create : Typed_sql_schema.Schema_ir.t -> Sql.t -> (t, Sql.error) Result.t

(** Returned fields, or an empty list for a command. *)
val fields : t -> field list
