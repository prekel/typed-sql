open! Base

(** Execution-adapter contract. Compile through [Typed_sql.Compiler], then
    consume the same opaque compiled value here. No AST constructors or unchecked
    conversions are exposed. Application code only needs [Typed_sql]. *)

module Db_type : sig
  (** A codec obtained from compiled parameters or result fields. *)
  type 'a t

  type packed_value = private Value : 'a t * 'a -> packed_value

  type _ view = private
    | Bool : bool view
    | Int : int view
    | Int64 : int64 view
    | Float : float view
    | Text : string view
    | Bytes : bytes view
    | Option : 'a t -> 'a option view
    | Map :
        { repr : 'a t
        ; encode : 'b -> ('a, string) Result.t
        ; decode : 'a -> ('b, string) Result.t
        ; name : string
        }
        -> 'b view

  (** Inspect codecs recursively. Mapped codecs must use their supplied encode
      and decode functions; replacing them with the representation loses checks. *)
  val view : 'a t -> 'a view

  val name : 'a t -> string
end

module Template : sig
  type t

  (** Visit fragments in SQL order. [text] receives compiler-generated SQL;
      [param] receives zero-based bind slots. Values must remain bound. *)
  val map : t -> text:(string -> 'a) -> param:(int -> 'a) -> 'a list
end

module Shape : sig
  (** Compilation identity including codec identities and result layout, but
      excluding parameter values, connections and generated source identities. *)
  type t

  val equal : t -> t -> bool
  val hash : t -> int
  val pp : Formatter.t -> t -> unit
  val to_string : t -> string
end

module Projection : sig
  (** A result plan extracted from a compiled query. *)
  type 'a t

  (** Build an applicative decoder, visiting fields in SELECT order. [field]
      describes one column; mapping functions must run when decoding a row. *)
  module Make (A : sig
      include Base.Applicative.S

      val field : 'a Db_type.t -> 'a t
    end) : sig
    val run : 'a t -> 'a A.t
  end
end

module Compiled_query : sig
  type 'a t = 'a Typed_sql.Compiled_query.t

  val template : 'a t -> Template.t
  val parameters : 'a t -> Db_type.packed_value list
  val projection : 'a t -> 'a Projection.t
  val shape : 'a t -> Shape.t
end

module Compiled_command : sig
  type t = Typed_sql.Compiled_command.t

  val template : t -> Template.t
  val parameters : t -> Db_type.packed_value list
  val shape : t -> Shape.t
end
