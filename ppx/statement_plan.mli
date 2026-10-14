open! Base

type field =
  { name : string
  ; codec : string
  ; nullable : bool
  }

type parameter =
  { value : Sql.parameter
  ; codec : string
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
    are harmless. EXCLUDED assignments require identical exact native types. *)
val create : Typed_sql_schema.Schema_ir.t -> Sql.t -> (t, Sql.error) Result.t

(** Returned fields, or an empty list for a command. *)
val fields : t -> field list
