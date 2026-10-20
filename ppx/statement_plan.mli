open! Base

(** One returned column in SQL order, including its transport codec and nullability. *)
type field =
  { name : string (** Result-column name in the SQL output layout. *)
  ; codec : Codec.t (** Resolved transport conversion for the non-null field value. *)
  ; nullable : bool (** Whether decoding wraps the field value in an option. *)
  }

(** A substitution paired with the conversion required by its resolved SQL context. *)
type parameter =
  { value : Sql.parameter
    (** The original source substitution, without evaluating its expression. *)
  ; codec : Codec.t (** Resolved PG'OCaml transport conversion for this substitution. *)
  }

(** Rows always contains at least one field. Command preserves the PG'OCaml
    unit-result contract for DML without RETURNING. *)
type result =
  | Command (** No returned fields; preserve the PG'OCaml unit-result contract. *)
  | Rows of field list (** Nonempty result layout in server output order. *)

(** Executable SQL and its ordered conversion plans. No connection or
    runtime OCaml parameter values are retained. *)
type t =
  { sql : string
    (** SQL rewritten to positional placeholders; OCaml values stay separate. *)
  ; result : result (** Command or row-result decoding contract. *)
  ; parameters : parameter list (** Bind occurrences in SQL/source order. *)
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
