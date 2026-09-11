open! Base

(** Execution-adapter contract. Compile through [Typed_sql.Compiler], then
    consume the same opaque compiled value here. No AST constructors or unchecked
    conversions are exposed. Application code only needs [Typed_sql]. *)

(** Read-only access to codecs carried by compiled statements. *)
module Db_type : sig
  (** A codec obtained from compiled parameters or result fields. *)
  type 'a t

  (** A parameter paired with the codec that knows its OCaml type. The private
      constructor permits exhaustive inspection but prevents adapters from
      constructing values outside compilation. *)
  type packed_value = private
    | Value : 'a t * 'a -> packed_value
    (** A value and the codec describing its hidden OCaml type. *)

  (** A read-only description of a codec. Primitive cases map directly to
      backend field types; compound cases must be interpreted recursively. *)
  type _ view = private
    | Bool : bool view (** SQL boolean. *)
    | Int : int view (** SQL integer represented as an OCaml [int]. *)
    | Int64 : int64 view (** SQL integer represented as an OCaml [int64]. *)
    | Float : float view (** SQL floating-point value. *)
    | Text : string view (** SQL text. *)
    | Bytes : bytes view (** SQL binary data. *)
    | Option : 'a t -> 'a option view
    (** A nullable value whose non-null representation uses the nested codec. *)
    | Map :
        { repr : 'a t (** The recursively interpreted database representation. *)
        ; encode : 'b -> ('a, string) Result.t
          (** Convert an application value before binding it. *)
        ; decode : 'a -> ('b, string) Result.t
          (** Convert a database field after reading it. *)
        ; name : string (** A diagnostic name supplied by the application. *)
        }
        -> 'b view (** A domain value encoded through another database representation. *)

  (** Inspect codecs recursively. Mapped codecs must use their supplied encode
      and decode functions; replacing them with the representation loses checks. *)
  val view : 'a t -> 'a view

  (** Return the diagnostic name assigned by the application codec. Names are
      descriptive and are not sufficient to establish codec identity. *)
  val name : 'a t -> string
end

(** Backend-neutral SQL fragments and parameter slots. *)
module Template : sig
  (** A sequence of compiler-generated SQL fragments and parameter slots. *)
  type t

  (** Visit fragments in SQL order. [text] receives compiler-generated SQL;
      [param] receives zero-based bind slots. Values must remain bound. *)
  val map : t -> text:(string -> 'a) -> param:(int -> 'a) -> 'a list
end

(** Stable identities for compiled statement shapes. *)
module Shape : sig
  (** Compilation identity including codec identities and result layout, but
      excluding parameter values, connections and generated source identities. *)
  type t

  (** Test whether two compilations have the same reusable shape. *)
  val equal : t -> t -> bool

  (** Hash a shape consistently with [equal]. *)
  val hash : t -> int

  (** Format the stable internal representation of a shape. *)
  val pp : Formatter.t -> t -> unit

  (** Return the stable internal representation of a shape. *)
  val to_string : t -> string
end

(** Typed result plans for adapter-specific row decoders. *)
module Projection : sig
  (** A result plan extracted from a compiled query. *)
  type 'a t

  (** Build an applicative decoder, visiting fields in SELECT order. [field]
      describes one column; mapping functions must run when decoding a row. *)
  module Make (A : sig
      (** Applicative operations used to combine field decoders. *)
      include Base.Applicative.S

      (** Describe how one selected field is decoded by the adapter. *)
      val field : 'a Db_type.t -> 'a t
    end) : sig
    (** Interpret a projection into the adapter's applicative decoder. Field
        order is the same as the rendered SELECT or RETURNING list. *)
    val run : 'a t -> 'a A.t
  end
end

(** Adapter access to a compiled row-returning statement. *)
module Compiled_query : sig
  (** The same opaque compiled query produced by [Typed_sql.Compiler]. *)
  type 'a t = 'a Typed_sql.Compiled_query.t

  (** Return the SQL template with parameter slots kept separate. *)
  val template : 'a t -> Template.t

  (** Return bound parameter values in slot order. *)
  val parameters : 'a t -> Db_type.packed_value list

  (** Return the typed result projection used to build a row decoder. *)
  val projection : 'a t -> 'a Projection.t

  (** Return the cache identity of the compiled statement and result layout. *)
  val shape : 'a t -> Shape.t
end

(** Adapter access to a compiled statement without returned rows. *)
module Compiled_command : sig
  (** The same opaque compiled command produced by [Typed_sql.Compiler]. *)
  type t = Typed_sql.Compiled_command.t

  (** Return the SQL template with parameter slots kept separate. *)
  val template : t -> Template.t

  (** Return bound parameter values in slot order. *)
  val parameters : t -> Db_type.packed_value list

  (** Return the cache identity of the compiled command. *)
  val shape : t -> Shape.t
end
