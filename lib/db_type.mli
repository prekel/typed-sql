open! Base

(** A database representation for an OCaml value. It is independent from any
    execution backend. *)
type 'a t

type packed = Pack : 'a t -> packed
type packed_value = Value : 'a t * 'a -> packed_value

type _ view =
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

val bool : bool t
val int : int t
val int64 : int64 t
val float : float t
val text : string t
val bytes : bytes t
val option : 'a t -> 'a option t

val map
  :  ?name:string
  -> encode:('b -> ('a, string) Result.t)
  -> decode:('a -> ('b, string) Result.t)
  -> 'a t
  -> 'b t

val view : 'a t -> 'a view
val name : 'a t -> string

(** Stable within one process and distinct for separately constructed mapped
    codecs, even when their display names match. *)
val fingerprint : 'a t -> string

(** An explicit witness that the database representation has a meaningful
    total ordering for the intended query. Mapped domain types only gain this
    capability through an explicit [map]. *)
module Ordering : sig
  type 'a t

  val int : int t
  val int64 : int64 t
  val float : float t
  val text : string t
  val bytes : bytes t
  val map : 'a t -> 'b t
end
