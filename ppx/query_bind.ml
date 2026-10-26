open! Base
module Shared = Typed_sql_ppx_cache.Query_bind

type error = Shared.error =
  { offset : int
  ; message : string
  }

type parameter = Shared.parameter =
  { expression : string
  ; optional : bool
  ; start : int
  ; stop : int
  }

type t = Shared.t =
  { sql : string
  ; parameters : parameter list
  }

let scan = Shared.scan

let error_to_string { offset; message } =
  "SQL byte " ^ Int.to_string offset ^ ": " ^ message
;;
