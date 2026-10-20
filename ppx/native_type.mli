open! Base

(** Exact types understood by offline PostgreSQL inference. [Unknown]
    is an unresolved literal type; domains and enums retain nominal identity. *)
type t =
  | Unknown (** An unresolved literal type; never valid for codec generation. *)
  | Domain of string * string * t
  (** Nominal schema/name identity and its exact base type. *)
  | Scalar of string (** Supported built-in PostgreSQL type name. *)
  | Enum of string * string
  (** Nominal schema/name identity of an enum transported as text. *)
  | Array of t (** Native array with a recursively resolved element type. *)

(** Domains use their exact base type for operator resolution and conversion. *)
val of_column : offset:int -> Typed_sql_schema.Schema_ir.column -> (t, Sql.error) Result.t

(** Resolve supported codecs from native metadata, unwrapping domains.
    Unsupported types return a diagnostic at [offset]. *)
val of_info
  :  offset:int
  -> Typed_sql_schema.Schema_ir.postgresql_type_info
  -> (t, Sql.error) Result.t

(** Choose the PG'OCaml conversion codec. The type must already have been
    resolved and validated; [Unknown] or unsupported scalars violate this invariant. *)
val codec : t -> Codec.t

(** Compare exact structure and nominal identities, including domain names. *)
val equal : t -> t -> bool

(** Test the supported operator compatibility relation, including known
    numeric/text families and domain base types; this is not catalog lookup. *)
val compatible : t -> t -> bool

(** Test whether the supported type admits comparison. Unknown types
    and [json] are rejected; array comparability follows the element type. *)
val comparable : t -> bool

(** Recognize built-in text, varchar and bpchar, including domain bases. *)
val text : t -> bool

(** Recognize supported built-in numeric types, including domain bases. *)
val numeric : t -> bool

(** Common type for fixed IN lists, restricted to known built-in implicit
    numeric/text coercions and identical nominal types. *)
val common : t -> t -> t option

(** Known built-in implicit and explicit conversions. Unknown casts are rejected. *)
val implicit : t -> t -> bool

(** Test the supported explicit conversion relation from the first type
    to the second. This deliberately does not consult server cast catalogs. *)
val explicit : t -> t -> bool

(** Preserve nominal domains for result type resolution; operators use [base]. *)
val base : t -> t

(** Resolve native metadata while retaining nominal domains in the result.
    Unsupported types return a diagnostic at [offset]. *)
val of_info_exact
  :  offset:int
  -> Typed_sql_schema.Schema_ir.postgresql_type_info
  -> (t, Sql.error) Result.t

(** Resolve a column's exact type, retaining domain identity and checking
    that its native type tree agrees with the recorded qualified type name. *)
val of_column_exact
  :  offset:int
  -> Typed_sql_schema.Schema_ir.column
  -> (t, Sql.error) Result.t
