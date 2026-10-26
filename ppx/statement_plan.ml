open! Base

type field =
  { name : string
  ; codec : Codec.t
  ; nullable : bool
  }

type parameter =
  { value : Query_bind.parameter
  ; codec : Codec.t
  }

type result =
  | Command
  | Rows of field list

type t =
  { sql : string
  ; result : result
  ; parameters : parameter list
  }

let fields plan =
  match plan.result with
  | Command -> []
  | Rows fields -> fields
;;
