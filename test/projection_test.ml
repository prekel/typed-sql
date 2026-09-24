open! Base
open Typed_sql
module B = Typed_sql_backend

module A :
  Base.Applicative.S2 with type ('a, 'requirements) t = ('a, 'requirements) Projection.t =
  Projection

let compile_exn
  : type row. Dialect.t -> (row, Dialect.portable) Projection.t -> row B.Compiled_query.t
  =
  fun dialect projection ->
  let query = Query.(from (Table.v_exn "items") |> select (fun _ -> projection)) in
  let statement =
    Statement.Portable.query_many (fun _ -> query)
    |> Result.map_error ~f:(fun (error : Statement.definition_error) ->
      Compile_error.to_string error.error)
    |> Result.ok_or_failwith
  in
  match B.Statement.resolve ~dialect () statement with
  | Ok (B.Statement.Query_execution { cardinality = B.Statement.Many; compiled }) ->
    compiled
  | Ok (B.Statement.Query_execution _) -> failwith "query cardinality changed"
  | Error _ -> failwith "query resolution failed"
;;

let%expect_test "applicative syntax preserves SELECT and bind order" =
  let projection =
    let open Projection.Let_syntax in
    let%map label = Projection.return "label"
    and values =
      A.all
        [ Projection.expr (Expr.constant Db_type.int 11)
        ; A.apply (A.return Int.succ) (Projection.expr (Expr.constant Db_type.int 22))
        ]
    and empty = A.all [] in
    label, values, empty
  in
  let compile dialect =
    let compiled = compile_exn dialect projection in
    let parameters =
      List.map
        (B.Compiled_query.parameters compiled)
        ~f:(fun (B.Db_type.Value (typ, value)) ->
          match B.Db_type.view typ with
          | Int -> (value : int)
          | _ -> failwith "unexpected parameter type")
    in
    assert (List.equal Int.equal parameters [ 11; 22 ]);
    compiled
  in
  Stdlib.print_endline (B.Compiled_query.sql (compile Dialect.Postgresql));
  [%expect
    {|
    SELECT
      $1,
      $2
    FROM "items" AS t0
    |}];
  Stdlib.print_endline (B.Compiled_query.sql (compile Dialect.Sqlite));
  [%expect
    {|
    SELECT
      ?1,
      ?2
    FROM "items" AS t0
    |}]
;;

module Decoder = struct
  type 'a t = unit -> 'a

  include Applicative.Make_using_map2 (struct
      type nonrec 'a t = 'a t

      let return value () = value
      let map t ~f () = f (t ())

      let map2 left right ~f () =
        let left = left () in
        let right = right () in
        f left right
      ;;

      let map = `Custom map
    end)

  let field : type a. a B.Db_type.t -> a t =
    fun db_type () ->
    match B.Db_type.view db_type with
    | Int -> 7
    | Text -> "Ada"
    | _ -> failwith "unsupported test codec"
  ;;
end

module Interpreter = B.Projection.Make (Decoder)

module Json_decoder = struct
  type 'a t = string -> ('a, string) Result.t

  include Applicative.Make_using_map2 (struct
      type nonrec 'a t = 'a t

      let return value _ = Ok value
      let map decoder ~f raw = Result.map (decoder raw) ~f

      let map2 left right ~f raw =
        let open Result.Let_syntax in
        let%bind left = left raw in
        let%map right = right raw in
        f left right
      ;;

      let map = `Custom map
    end)

  let field : type a. a B.Db_type.t -> a t =
    fun db_type raw ->
    ignore (B.Db_type.name db_type : string);
    match B.Db_type.view db_type with
    | Map { repr; encode; decode; _ } ->
      (match B.Db_type.view repr with
       | Text ->
         let result = decode raw in
         Result.iter result ~f:(fun value -> ignore (encode value : (_, string) Result.t));
         result
       | _ -> Error "expected text transport")
    | _ -> Error "expected mapped multiset codec"
  ;;
end

module Json_interpreter = B.Projection.Make (Json_decoder)

let multiset_decoder projection =
  let inner = Query.(from (Table.v_exn "nested_items") |> select (fun _ -> projection)) in
  let compiled = compile_exn Dialect.Sqlite (Query.multiset inner) in
  Json_interpreter.run (B.Compiled_query.projection compiled)
;;

let%test_unit "backend interpreter defers maps until decoding" =
  let mapped = ref 0 in
  let projection =
    let open Projection.Let_syntax in
    let%map id = Projection.expr (Expr.constant Db_type.int 7)
    and name = Projection.expr (Expr.constant Db_type.text "Ada")
    and suffix = Projection.return "!" in
    Int.incr mapped;
    Int.to_string id ^ ": " ^ name ^ suffix
  in
  let compiled = compile_exn Dialect.Sqlite projection in
  let decode = Interpreter.run (B.Compiled_query.projection compiled) in
  assert (Int.(!mapped = 0));
  assert (String.equal (decode ()) "7: Ada!");
  assert (Int.(!mapped = 1))
;;

let%test_unit "backend multiset codec rejects malformed transport values" =
  let int_decoder = multiset_decoder (Projection.expr (Expr.constant Db_type.int 0)) in
  assert (
    Result.equal (List.equal Int.equal) String.equal (int_decoder "[[1]]") (Ok [ 1 ]));
  List.iter [ "not JSON"; "{}"; "[{}]"; "[[]]"; "[[1,2]]"; "[[true]]" ] ~f:(fun raw ->
    assert (Result.is_error (int_decoder raw)));
  let bool_decoder =
    multiset_decoder (Projection.expr (Expr.constant Db_type.bool false))
  in
  assert (
    Result.equal
      (List.equal Bool.equal)
      String.equal
      (bool_decoder "[[true],[false]]")
      (Ok [ true; false ]));
  let timestamp =
    match Ptime.of_rfc3339 "2024-01-02T03:04:05Z" with
    | Ok (value, _, _) -> value
    | Error _ -> failwith "invalid timestamp fixture"
  in
  let timestamp_decoder =
    multiset_decoder (Projection.expr (Expr.constant Db_type.timestamp timestamp))
  in
  match timestamp_decoder "[[\"2024-01-02T03:04:05Z\"]]" with
  | Ok [ decoded ] -> assert (Ptime.equal decoded timestamp)
  | Ok _ | Error _ -> failwith "timestamp multiset transport did not decode"
;;

let%expect_test "multiset decoder errors identify root, row, and field locations" =
  let decode = multiset_decoder (Projection.expr (Expr.constant Db_type.int 0)) in
  let print_error raw =
    match decode raw with
    | Ok _ -> failwith "malformed multiset unexpectedly decoded"
    | Error message -> Stdlib.print_endline message
  in
  print_error "{}";
  [%expect {| multiset root: expected array, got compound |}];
  print_error "[{}]";
  [%expect {| multiset element 1: expected row array, got compound |}];
  print_error "[[true]]";
  [%expect {| multiset element 1.1: expected int, got boolean |}]
;;
