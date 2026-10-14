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

type t =
  { sql : string
  ; fields : field list
  ; parameters : parameter list
  }

(** Resolve sources and exact codecs. Only selected and parameter columns
    need supported type metadata; unused unsupported columns are harmless. *)
val create : Typed_sql_schema.Schema_ir.t -> Sql.t -> (t, Sql.error) Result.t
