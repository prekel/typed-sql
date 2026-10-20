open! Base

(** Logical PostgreSQL type metadata shared with schema snapshots. *)
module Type_info = Typed_sql_schema.Schema_ir

(** Embedding category derived from an accepted server statement and its
    result shape. Unsupported entries require metadata refresh or supported SQL. *)
type kind =
  | Select (** A SELECT result eligible for query embedding subject to placement rules. *)
  | Returning (** A data-modifying statement returning rows. *)
  | Command (** A data-modifying statement without returned rows. *)
  | Unsupported (** Metadata retained for SQL that this PPX cannot safely classify. *)

(** One described output field, retaining exact native type and nullability. *)
type field =
  { name : string (** Result-column name in the SQL output layout. *)
  ; typ : Type_info.postgresql_type_info
    (** Exact logical PostgreSQL type, with no database-specific OID. *)
  ; nullable : bool (** Whether decoding wraps the field value in an option. *)
  }

(** Metadata keyed by exact rewritten SQL. Parameter and result order
    must match Prepare/Describe; [top_level_only] forbids nested embedding. *)
type entry =
  { sql : string
    (** Exact SQL after rewriting OCaml substitutions to positional placeholders. *)
  ; kind : kind
    (** Embedding category inferred from the outer operation and result shape. *)
  ; top_level_only : bool
    (** True when row locks or modifying CTEs prohibit nested embedding. *)
  ; parameters : Type_info.postgresql_type_info list
    (** Parameter types in positional-placeholder order. *)
  ; result : field list option
    (** Absent for a command; otherwise a nonempty ordered output layout. *)
  }

(** Validated logical metadata for one role and search-path configuration. *)
type t

(** Logical metadata only; no driver or PGOCaml codec is used here. *)
val create : role:string -> search_path:string -> entry list -> (t, string) Result.t

(** Return entries in cache order without performing database access. *)
val entries : t -> entry list

(** Look up exact rewritten SQL; whitespace and other source bytes are significant. *)
val find : t -> sql:string -> entry option

(** Classify an operation and whether it returns rows for PPX embedding. *)
val kind : operation:Query_kind.operation -> rows:bool -> kind

(** Return the stable serialized spelling of a cache entry kind. *)
val kind_to_string : kind -> string

(** v1 remains readable with Unsupported kind, requiring refresh for query PPX. *)
val of_string : string -> (t, string) Result.t

(** Serialize validated logical metadata, including operation kind and
    top-level placement restrictions. Runtime values and database OIDs are absent. *)
val to_string : t -> string

(** Generate OCaml registration source for the selected PPX driver.
    Metadata is embedded; the generated module does not open a JSON file. *)
val codegen : target:[ `Pgocaml_ppx | `Typed_sql_ppx ] -> t -> string
