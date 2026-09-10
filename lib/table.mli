open! Base

(** A table descriptor. The phantom row type distinguishes schemas at compile
    time and is normally declared abstract inside a generated table module. *)
type 'row t

val v : ?schema:Identifier.t -> Identifier.t -> 'row t
val v_exn : ?schema:string -> string -> 'row t
val name : 'row t -> Identifier.t
val schema : 'row t -> Identifier.t Option.t
