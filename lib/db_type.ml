open! Base

type _ t =
  | Bool_type : bool t
  | Int_type : int t
  | Int64_type : int64 t
  | Float_type : float t
  | Text_type : string t
  | Bytes_type : bytes t
  | Date_type : Date.t t
  | Timestamp_type : Ptime.t t
  | Uuid_type : Uuid.t t
  | Option_type : 'a t -> 'a option t
  | Map_type :
      { repr : 'a t
      ; encode : 'b -> ('a, string) Result.t
      ; decode : 'a -> ('b, string) Result.t
      ; name : string
      ; id : int
      }
      -> 'b t
  | Json_result_type :
      { fields : packed list
      ; decode_json : path:int list -> Yojson.Safe.t -> ('a, string) Result.t
      }
      -> 'a t

and packed = Pack : 'a t -> packed

type packed_value = Value : 'a t * 'a -> packed_value

type _ view =
  | Bool : bool view
  | Int : int view
  | Int64 : int64 view
  | Float : float view
  | Text : string view
  | Bytes : bytes view
  | Date : Date.t view
  | Timestamp : Ptime.t view
  | Uuid : Uuid.t view
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
let date = Date_type
let timestamp = Timestamp_type
let uuid = Uuid_type
let option typ = Option_type typ
let next_mapping_id = Atomic.make 0

let rec name : type a. a t -> string = function
  | Bool_type -> "bool"
  | Int_type -> "int"
  | Int64_type -> "int64"
  | Float_type -> "float"
  | Text_type -> "text"
  | Bytes_type -> "bytes"
  | Date_type -> "date"
  | Timestamp_type -> "timestamp"
  | Uuid_type -> "uuid"
  | Option_type typ -> "option(" ^ name typ ^ ")"
  | Map_type mapping -> mapping.name
  | Json_result_type _ -> "multiset"
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
  | Date_type -> "date"
  | Timestamp_type -> "timestamp"
  | Uuid_type -> "uuid"
  | Option_type typ -> "option(" ^ fingerprint typ ^ ")"
  | Map_type { repr; id; _ } -> "map#" ^ Int.to_string id ^ "(" ^ fingerprint repr ^ ")"
  | Json_result_type { fields; _ } ->
    let fields =
      List.map fields ~f:(fun (Pack field) -> fingerprint field) |> String.concat ~sep:","
    in
    "multiset(" ^ fields ^ ")"
;;

let json_error message = Error ("invalid multiset JSON: " ^ message)
let json_result ~fields ~decode_json = Json_result_type { fields; decode_json }

let is_json_result : type a. a t -> bool = function
  | Json_result_type _ -> true
  | _ -> false
;;

let rec unsupported_multiset_type
  : type a. path:int list -> a t -> (int list * string) option
  =
  fun ~path -> function
  | Bytes_type -> Some (path, "bytes")
  | Option_type typ -> unsupported_multiset_type ~path typ
  | Map_type { repr; _ } -> unsupported_multiset_type ~path repr
  | Json_result_type { fields; _ } ->
    List.find_mapi fields ~f:(fun index (Pack field) ->
      unsupported_multiset_type ~path:(path @ [ index + 1 ]) field)
  | Bool_type
  | Int_type
  | Int64_type
  | Float_type
  | Text_type
  | Date_type
  | Timestamp_type
  | Uuid_type -> None
;;

let view : type a. a t -> a view = function
  | Bool_type -> Bool
  | Int_type -> Int
  | Int64_type -> Int64
  | Float_type -> Float
  | Text_type -> Text
  | Bytes_type -> Bytes
  | Date_type -> Date
  | Timestamp_type -> Timestamp
  | Uuid_type -> Uuid
  | Option_type typ -> Option typ
  | Map_type { repr; encode; decode; name; _ } -> Map { repr; encode; decode; name }
  | Json_result_type { decode_json; _ } ->
    Map
      { repr = Text_type
      ; encode = (fun _ -> Error "multiset values are result-only")
      ; decode =
          (fun value ->
            try Yojson.Safe.from_string value |> decode_json ~path:[] with
            | Yojson.Json_error message -> json_error message)
      ; name = "multiset"
      }
;;
