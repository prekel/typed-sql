open! Base

type _ t =
  | Bool_type : bool t
  | Int_type : int t
  | Int64_type : int64 t
  | Float_type : float t
  | Text_type : string t
  | Bytes_type : bytes t
  | Option_type : 'a t -> 'a option t
  | Map_type :
      { repr : 'a t
      ; encode : 'b -> ('a, string) Result.t
      ; decode : 'a -> ('b, string) Result.t
      ; name : string
      ; id : int
      }
      -> 'b t

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

let bool = Bool_type
let int = Int_type
let int64 = Int64_type
let float = Float_type
let text = Text_type
let bytes = Bytes_type
let option typ = Option_type typ
let next_mapping_id = Atomic.make 0

let rec name : type a. a t -> string = function
  | Bool_type -> "bool"
  | Int_type -> "int"
  | Int64_type -> "int64"
  | Float_type -> "float"
  | Text_type -> "text"
  | Bytes_type -> "bytes"
  | Option_type typ -> "option(" ^ name typ ^ ")"
  | Map_type mapping -> mapping.name
;;

let map ?name:custom_name ~encode ~decode repr =
  let name = Option.value custom_name ~default:("mapped(" ^ name repr ^ ")") in
  let id = Atomic.fetch_and_add next_mapping_id 1 in
  Map_type { repr; encode; decode; name; id }
;;

let rec fingerprint : type a. a t -> string = function
  | Bool_type -> "bool"
  | Int_type -> "int"
  | Int64_type -> "int64"
  | Float_type -> "float"
  | Text_type -> "text"
  | Bytes_type -> "bytes"
  | Option_type typ -> "option(" ^ fingerprint typ ^ ")"
  | Map_type { repr; id; _ } -> "map#" ^ Int.to_string id ^ "(" ^ fingerprint repr ^ ")"
;;

let view : type a. a t -> a view = function
  | Bool_type -> Bool
  | Int_type -> Int
  | Int64_type -> Int64
  | Float_type -> Float
  | Text_type -> Text
  | Bytes_type -> Bytes
  | Option_type typ -> Option typ
  | Map_type { repr; encode; decode; name; _ } -> Map { repr; encode; decode; name }
;;

module Ordering = struct
  type 'a t = unit

  let int = ()
  let int64 = ()
  let float = ()
  let text = ()
  let bytes = ()
  let map _ = ()
end
