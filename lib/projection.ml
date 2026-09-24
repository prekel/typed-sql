open! Base

type (_, +_) t =
  | Pure_projection : 'a -> ('a, 'requirements) t
  | Expr_projection : ('a, 'requirements) Expr.t -> ('a, 'requirements) t
  | Map_projection : ('a -> 'b) * ('a, 'requirements) t -> ('b, 'requirements) t
  | Both_projection :
      ('a, 'requirements) t * ('b, 'requirements) t
      -> ('a * 'b, 'requirements) t

type 'a erased = Erased : ('a, 'requirements) t -> 'a erased

let expr expression = Expr_projection expression
let pair left right = Both_projection (expr left, expr right)

let rec types : type a requirements. (a, requirements) t -> Db_type.packed list = function
  | Pure_projection _ -> []
  | Expr_projection expression -> [ Db_type.Pack (Expr.db_type expression) ]
  | Map_projection (_, projection) -> types projection
  | Both_projection (left, right) -> types left @ types right
;;

let json_location path =
  List.foldi path ~init:"multiset root" ~f:(fun index location component ->
    if Int.(index = 0) then
      "multiset element " ^ Int.to_string component
    else
      location ^ "." ^ Int.to_string component)
;;

let json_error ~path expected actual =
  Error
    (Stdlib.Format.asprintf
       "%s: expected %s, got %s"
       (json_location path)
       expected
       actual)
;;

let json_kind = function
  | `Null -> "null"
  | `Bool _ -> "boolean"
  | `Int _ | `Intlit _ | `Float _ -> "number"
  | `String _ -> "string"
  | `Assoc _ | `List _ | `Tuple _ | `Variant _ -> "compound"
;;

let timestamp_of_string value =
  let value =
    if Int.(String.length value > 10) && Char.equal value.[10] ' ' then
      String.sub value ~pos:0 ~len:10 ^ "T" ^ String.drop_prefix value 11
    else
      value
  in
  let value =
    if Int.(String.length value <= 10) || not (Char.equal value.[10] 'T') then
      value
    else (
      let time = String.drop_prefix value 11 in
      let has_timezone =
        String.is_suffix time ~suffix:"Z"
        || String.is_suffix time ~suffix:"z"
        || String.exists time ~f:(function
          | '+' | '-' -> true
          | _ -> false)
      in
      if has_timezone then
        value
      else
        value ^ "Z")
  in
  match Ptime.of_rfc3339 value with
  | Ok (timestamp, _, _) -> Some timestamp
  | Error _ -> None
;;

let rec decode_db_type
  : type a. path:int list -> a Db_type.t -> Yojson.Safe.t -> (a, string) Result.t
  =
  fun ~path db_type json ->
  match db_type, json with
  | Db_type.Option_type _, `Null -> Ok None
  | Db_type.Option_type inner, value ->
    Result.map (decode_db_type ~path inner value) ~f:Option.some
  | Db_type.Bool_type, `Bool value -> Ok value
  | Db_type.Bool_type, `Int 0 -> Ok false
  | Db_type.Bool_type, `Int 1 -> Ok true
  | Db_type.Int_type, `Int value -> Ok value
  | Db_type.Int_type, `Intlit value -> json_error ~path "int" value
  | Db_type.Int64_type, `Int value -> Ok (Int64.of_int value)
  | Db_type.Int64_type, `Intlit value ->
    (try Ok (Int64.of_string value) with
     | Failure _ -> json_error ~path "int64" value)
  | Db_type.Float_type, `Float value -> Ok value
  | Db_type.Float_type, `Int value -> Ok (Float.of_int value)
  | Db_type.Float_type, `Intlit value -> Ok (Float.of_string value)
  | Db_type.Text_type, `String value -> Ok value
  | Db_type.Date_type, `String value ->
    (match Date.of_string value with
     | Some date -> Ok date
     | None -> json_error ~path "date" value)
  | Db_type.Timestamp_type, `String value ->
    (match timestamp_of_string value with
     | Some timestamp -> Ok timestamp
     | None -> json_error ~path "timestamp" value)
  | Db_type.Uuid_type, `String value ->
    (match Uuid.of_string value with
     | Some uuid -> Ok uuid
     | None -> json_error ~path "uuid" value)
  | Db_type.Map_type { repr; decode; _ }, value ->
    let open Result.Let_syntax in
    let%bind repr = decode_db_type ~path repr value in
    decode repr
    |> Result.map_error ~f:(fun message ->
      Stdlib.Format.asprintf "%s: %s" (json_location path) message)
  | Db_type.Json_result_type { decode_json; _ }, value -> decode_json ~path value
  | Db_type.Bytes_type, _ -> assert false
  | Db_type.Bool_type, value -> json_error ~path "bool" (json_kind value)
  | Db_type.Int_type, value -> json_error ~path "int" (json_kind value)
  | Db_type.Int64_type, value -> json_error ~path "int64" (json_kind value)
  | Db_type.Float_type, value -> json_error ~path "float" (json_kind value)
  | Db_type.Text_type, value -> json_error ~path "text" (json_kind value)
  | Db_type.Date_type, value -> json_error ~path "date" (json_kind value)
  | Db_type.Timestamp_type, value -> json_error ~path "timestamp" (json_kind value)
  | Db_type.Uuid_type, value -> json_error ~path "uuid" (json_kind value)
;;

let rec decode_json_fields
  : type a requirements.
    path:int list
    -> field:int
    -> (a, requirements) t
    -> Yojson.Safe.t list
    -> (a * Yojson.Safe.t list, string) Result.t
  =
  fun ~path ~field projection values ->
  match projection with
  | Pure_projection value -> Ok (value, values)
  | Expr_projection expression ->
    let value = List.hd_exn values in
    let rest = List.tl_exn values in
    Result.map
      (decode_db_type ~path:(path @ [ field ]) (Expr.db_type expression) value)
      ~f:(fun decoded -> decoded, rest)
  | Map_projection (f, projection) ->
    Result.map
      (decode_json_fields ~path ~field projection values)
      ~f:(fun (value, rest) -> f value, rest)
  | Both_projection (left, right) ->
    let next_field = field + List.length (expressions left) in
    let open Result.Let_syntax in
    let%bind left, values = decode_json_fields ~path ~field left values in
    let%map right, values = decode_json_fields ~path ~field:next_field right values in
    (left, right), values

and expressions : type a requirements. (a, requirements) t -> Ast.expr list = function
  | Pure_projection _ -> []
  | Expr_projection expression -> [ Expr.node expression ]
  | Map_projection (_, projection) -> expressions projection
  | Both_projection (left, right) -> expressions left @ expressions right
;;

let json_list ~path ~expected = function
  | `List values -> Ok values
  | value -> json_error ~path expected (json_kind value)
;;

let decode_json_rows projection ~path json =
  let open Result.Let_syntax in
  let%bind rows = json_list ~path ~expected:"array" json in
  List.mapi rows ~f:(fun index row ->
    let path = path @ [ index + 1 ] in
    let%bind fields = json_list ~path ~expected:"row array" row in
    let expected = List.length (expressions projection) in
    if Int.(List.length fields <> expected) then
      json_error ~path "projected field count" "different field count"
    else
      Result.map (decode_json_fields ~path ~field:1 projection fields) ~f:fst)
  |> Result.all
;;

let multiset_expression ~node projection =
  let fields = types projection in
  let db_type = Db_type.json_result ~fields ~decode_json:(decode_json_rows projection) in
  Expr.create node db_type
;;

let multiset_agg ?filter ?(order_by = []) projection =
  let node =
    Ast.Aggregate
      (Ast.Multiset_agg
         { fields = expressions projection
         ; field_types = types projection
         ; filter = Option.map filter ~f:Condition.node
         ; order_by = List.map order_by ~f:Aggregate_order.ast
         })
  in
  expr (multiset_expression ~node projection)
;;

let multiset_subquery query projection =
  let node = Ast.Multiset_subquery { Ast.query; field_types = types projection } in
  expr (multiset_expression ~node projection)
;;

include Applicative.Make2_using_map2 (struct
    type nonrec ('a, 'requirements) t = ('a, 'requirements) t

    let return value = Pure_projection value
    let map projection ~f = Map_projection (f, projection)
    let map2 left right ~f = map (Both_projection (left, right)) ~f:(fun (a, b) -> f a b)
    let map = `Custom map
  end)

module Let_syntax = struct
  let return = return

  include Applicative_infix

  module Let_syntax = struct
    let return = return
    let map = map
    let both = both

    module Open_on_rhs = struct end
  end
end

module Make (A : sig
    include Applicative.S

    val expr : ('a, 'requirements) Expr.t -> 'a t
  end) =
struct
  let rec run_t : type a requirements. (a, requirements) t -> a A.t = function
    | Pure_projection value -> A.return value
    | Expr_projection expression -> A.expr expression
    | Map_projection (f, projection) -> A.map (run_t projection) ~f
    | Both_projection (left, right) ->
      let left = run_t left in
      let right = run_t right in
      A.both left right
  ;;

  let run (Erased projection) = run_t projection
end

let erase projection = Erased projection
