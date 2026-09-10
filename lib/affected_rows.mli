open! Base

type t =
  | Known of int
  | Unknown

val pp : Formatter.t -> t -> unit
