open! Base

type t = string

let equal = String.equal
let hash = String.hash
let pp formatter shape = Stdlib.Format.pp_print_string formatter shape
let to_string shape = shape

module Private = struct
  let create shape = shape
end
