open! Base

type _ t =
  | Bool_type : bool t
  | Int_type : int t
  | Int64_type : int64 t
  | Float_type : float t
  | Numeric_type : Decimal.t t
  | Text_type : string t
  | Bytes_type : bytes t
  | Date_type : Date.t t
  | Timestamp_type : Ptime.t t
  | Uuid_type : Uuid.t t
  | Named_type :
      { schema : Identifier.t
      ; name : Identifier.t
      ; repr : 'a t
      }
      -> 'a t
  | Array_type : 'a t -> 'a Pg_array.t t
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
  | Numeric : Decimal.t view
  | Text : string view
  | Bytes : bytes view
  | Date : Date.t view
  | Timestamp : Ptime.t view
  | Uuid : Uuid.t view
  | Named :
      { schema : string
      ; name : string
      ; repr : 'a t
      }
      -> 'a view
  | Array :
      { encode : 'a -> (string, string) Result.t
      ; decode : string -> ('a, string) Result.t
      }
      -> 'a view
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
let numeric = Numeric_type
let text = Text_type
let bytes = Bytes_type
let date = Date_type
let timestamp = Timestamp_type
let uuid = Uuid_type

type 'a orderable = 'a t

module Orderable = struct
  type 'a t = 'a orderable

  let int = int
  let int64 = int64
  let float = float
  let text = text
  let date = date
  let timestamp = timestamp
  let uuid = uuid
end

let option typ = Option_type typ
let next_mapping_id = Atomic.make 0

let rec name : type a. a t -> string = function
  | Bool_type -> "bool"
  | Int_type -> "int"
  | Int64_type -> "int64"
  | Float_type -> "float"
  | Numeric_type -> "numeric"
  | Text_type -> "text"
  | Bytes_type -> "bytes"
  | Date_type -> "date"
  | Timestamp_type -> "timestamp"
  | Uuid_type -> "uuid"
  | Named_type { schema; name; _ } ->
    Identifier.to_string schema ^ "." ^ Identifier.to_string name
  | Array_type element -> "array(" ^ name element ^ ")"
  | Option_type typ -> "option(" ^ name typ ^ ")"
  | Map_type mapping -> mapping.name
  | Json_result_type _ -> "multiset"
;;

let map_with_id ?name:custom_name ~id ~encode ~decode repr =
  let name = Option.value custom_name ~default:("mapped(" ^ name repr ^ ")") in
  Map_type { repr; encode; decode; name; id }
;;

let map ?name ~encode ~decode repr =
  map_with_id ?name ~id:(Atomic.fetch_and_add next_mapping_id 1) ~encode ~decode repr
;;

let rec fingerprint : type a. a t -> string = function
  | Bool_type -> "bool"
  | Int_type -> "int"
  | Int64_type -> "int64"
  | Float_type -> "float"
  | Numeric_type -> "numeric"
  | Text_type -> "text"
  | Bytes_type -> "bytes"
  | Date_type -> "date"
  | Timestamp_type -> "timestamp"
  | Uuid_type -> "uuid"
  | Named_type { schema; name; repr } ->
    "named("
    ^ Identifier.to_string schema
    ^ "."
    ^ Identifier.to_string name
    ^ ","
    ^ fingerprint repr
    ^ ")"
  | Array_type element -> "array(" ^ fingerprint element ^ ")"
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
  | Numeric_type -> Some (path, "numeric")
  | Named_type { repr; _ } -> unsupported_multiset_type ~path repr
  | Array_type _ -> Some (path, "array")
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

let rec pg_text_encode : type a. a t -> a -> (string, string) Result.t =
  fun typ value ->
  match typ with
  | Bool_type -> Ok (Bool.to_string value)
  | Int_type -> Ok (Int.to_string value)
  | Int64_type -> Ok (Int64.to_string value)
  | Float_type -> Ok (Stdlib.Printf.sprintf "%.17g" value)
  | Numeric_type -> Ok (Decimal.to_string value)
  | Text_type -> Ok value
  | Bytes_type ->
    let buffer = Buffer.create (2 + (Bytes.length value * 2)) in
    Buffer.add_string buffer "\\x";
    for index = 0 to Bytes.length value - 1 do
      Buffer.add_string
        buffer
        (Stdlib.Printf.sprintf "%02x" (Char.to_int (Bytes.get value index)))
    done;
    Ok (Buffer.contents buffer)
  | Date_type -> Ok (Date.to_string value)
  | Timestamp_type -> Ok (Ptime.to_rfc3339 value)
  | Uuid_type -> Ok (Uuid.to_string value)
  | Named_type { repr; _ } -> pg_text_encode repr value
  | Array_type element -> Pg_array.to_string ~encode:(pg_text_encode element) value
  | Option_type _ -> Error "array elements use a single nullable layer"
  | Map_type { repr; encode; _ } ->
    let open Result.Let_syntax in
    let%bind represented = encode value in
    pg_text_encode repr represented
  | Json_result_type _ -> Error "multiset values are result-only"
;;

let rec pg_text_decode : type a. a t -> string -> (a, string) Result.t =
  fun typ source ->
  let required option message =
    match option with
    | Some value -> Ok value
    | None -> Error message
  in
  match typ with
  | Bool_type ->
    (match String.lowercase source with
     | "t" | "true" -> Ok true
     | "f" | "false" -> Ok false
     | _ -> Error "invalid boolean array element")
  | Int_type -> required (Int.of_string_opt source) "invalid integer"
  | Int64_type -> required (Int64.of_string_opt source) "invalid int64"
  | Float_type -> required (Float.of_string_opt source) "invalid float"
  | Numeric_type -> required (Decimal.of_string source) "invalid numeric"
  | Text_type -> Ok source
  | Bytes_type ->
    if String.is_prefix source ~prefix:"\\x" then (
      let hex = String.drop_prefix source 2 in
      if Int.(String.length hex % 2 <> 0) then
        Error "invalid bytea"
      else (
        let bytes = Bytes.create (String.length hex / 2) in
        let rec loop index =
          if Int.(index = Bytes.length bytes) then
            Ok bytes
          else (
            let pair = String.sub hex ~pos:(index * 2) ~len:2 in
            match Int.of_string_opt ("0x" ^ pair) with
            | None -> Error "invalid bytea"
            | Some value ->
              Bytes.set bytes index (Char.of_int_exn value);
              loop (index + 1))
        in
        loop 0))
    else
      Error "unsupported bytea array output"
  | Date_type -> required (Date.of_string source) "invalid date"
  | Timestamp_type ->
    (match Ptime.of_rfc3339 source with
     | Ok (value, _, _) -> Ok value
     | Error _ -> Error "invalid timestamptz")
  | Uuid_type -> required (Uuid.of_string source) "invalid UUID"
  | Named_type { repr; _ } -> pg_text_decode repr source
  | Array_type element -> Pg_array.of_string ~decode:(pg_text_decode element) source
  | Option_type _ -> Error "array elements use a single nullable layer"
  | Map_type { repr; decode; _ } ->
    let open Result.Let_syntax in
    let%bind repr = pg_text_decode repr source in
    decode repr
  | Json_result_type _ -> Error "multiset values are result-only"
;;

module Postgresql = struct
  let named ~schema ~name repr = Named_type { schema; name; repr }
  let array element = Array_type element
  let encode_text = pg_text_encode
  let decode_text = pg_text_decode

  let json =
    let repr =
      named
        ~schema:(Identifier.of_string_exn "pg_catalog")
        ~name:(Identifier.of_string_exn "json")
        text
    in
    map_with_id
      ~id:(-1)
      ~name:"json"
      ~encode:(fun value -> Ok (Yojson.Safe.to_string value))
      ~decode:(fun source ->
        try Ok (Yojson.Safe.from_string source) with
        | Yojson.Json_error message -> Error message)
      repr
  ;;

  let jsonb =
    let repr =
      named
        ~schema:(Identifier.of_string_exn "pg_catalog")
        ~name:(Identifier.of_string_exn "jsonb")
        text
    in
    map_with_id
      ~id:(-2)
      ~name:"jsonb"
      ~encode:(fun value -> Ok (Yojson.Safe.to_string value))
      ~decode:(fun source ->
        try Ok (Yojson.Safe.from_string source) with
        | Yojson.Json_error message -> Error message)
      repr
  ;;

  let local_timestamp =
    map_with_id
      ~id:(-3)
      ~name:"timestamp without time zone"
      ~encode:(fun value -> Ok (Local_timestamp.to_string value))
      ~decode:Local_timestamp.of_string
      (named
         ~schema:(Identifier.of_string_exn "pg_catalog")
         ~name:(Identifier.of_string_exn "timestamp")
         text)
  ;;

  let interval =
    map_with_id
      ~id:(-4)
      ~name:"interval"
      ~encode:(fun value -> Ok (Interval.to_string value))
      ~decode:Interval.of_string
      (named
         ~schema:(Identifier.of_string_exn "pg_catalog")
         ~name:(Identifier.of_string_exn "interval")
         text)
  ;;
end

let quote_identifier value =
  "\""
  ^ String.substr_replace_all (Identifier.to_string value) ~pattern:"\"" ~with_:"\"\""
  ^ "\""
;;

let rec postgresql_type_name : type a. a t -> string = function
  | Bool_type -> "boolean"
  | Int_type -> "integer"
  | Int64_type -> "bigint"
  | Float_type -> "double precision"
  | Numeric_type -> "numeric"
  | Text_type -> "text"
  | Bytes_type -> "bytea"
  | Date_type -> "date"
  | Timestamp_type -> "timestamp with time zone"
  | Uuid_type -> "uuid"
  | Named_type { schema; name; _ } ->
    quote_identifier schema ^ "." ^ quote_identifier name
  | Array_type element -> postgresql_type_name element ^ "[]"
  | Option_type inner -> postgresql_type_name inner
  | Map_type { repr; _ } -> postgresql_type_name repr
  | Json_result_type _ -> "jsonb"
;;

let rec needs_postgresql_cast : type a. a t -> bool = function
  | Named_type _ | Array_type _ -> true
  | Option_type inner -> needs_postgresql_cast inner
  | Map_type { repr; _ } -> needs_postgresql_cast repr
  | Bool_type
  | Int_type
  | Int64_type
  | Float_type
  | Numeric_type
  | Text_type
  | Bytes_type
  | Date_type
  | Timestamp_type
  | Uuid_type
  | Json_result_type _ -> false
;;

let rec sqlite_unsupported_type : type a. a t -> string option = function
  | Numeric_type -> Some "numeric"
  | Named_type _ | Array_type _ -> Some "postgresql type"
  | Option_type inner -> sqlite_unsupported_type inner
  | Map_type { repr; _ } -> sqlite_unsupported_type repr
  | Bool_type
  | Int_type
  | Int64_type
  | Float_type
  | Text_type
  | Bytes_type
  | Date_type
  | Timestamp_type
  | Uuid_type
  | Json_result_type _ -> None
;;

let view : type a. a t -> a view = function
  | Bool_type -> Bool
  | Int_type -> Int
  | Int64_type -> Int64
  | Float_type -> Float
  | Numeric_type -> Numeric
  | Text_type -> Text
  | Bytes_type -> Bytes
  | Date_type -> Date
  | Timestamp_type -> Timestamp
  | Uuid_type -> Uuid
  | Named_type { schema; name; repr } ->
    Named { schema = Identifier.to_string schema; name = Identifier.to_string name; repr }
  | Array_type element ->
    Array
      { encode = Pg_array.to_string ~encode:(pg_text_encode element)
      ; decode = Pg_array.of_string ~decode:(pg_text_decode element)
      }
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
