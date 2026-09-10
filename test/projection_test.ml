open! Base
open Typed_sql
module B = Typed_sql_backend
module A : Base.Applicative.S with type 'a t = 'a Projection.t = Projection

let compile_exn dialect projection =
  Query.from (Table.v_exn "items") ~select:(fun _ -> projection)
  |> Query.to_result
  |> Compiler.compile ~dialect
  |> Result.map_error ~f:Compile_error.to_string
  |> Result.ok_or_failwith
;;

let%expect_test "applicative syntax preserves SELECT and bind order" =
  let projection =
    let open Projection.Let_syntax in
    let%map label = Projection.return "label"
    and values =
      A.all
        [ Projection.expr (Expr.param Db_type.int 11)
        ; A.apply (A.return Int.succ) (Projection.expr (Expr.param Db_type.int 22))
        ]
    and empty = A.all [] in
    label, values, empty
  in
  List.iter [ Dialect.Postgresql; Dialect.Sqlite ] ~f:(fun dialect ->
    let compiled = compile_exn dialect projection in
    Stdlib.print_endline (Compiled_query.sql compiled);
    let parameters =
      List.map
        (B.Compiled_query.parameters compiled)
        ~f:(fun (B.Db_type.Value (typ, value)) ->
          match B.Db_type.view typ with
          | Int -> Int.to_string value
          | _ -> failwith "unexpected parameter type")
    in
    Stdlib.print_endline (String.concat ~sep:", " parameters));
  [%expect
    {|
    SELECT $1, $2 FROM "items" AS t0
    11, 22
    SELECT ?1, ?2 FROM "items" AS t0
    11, 22 |}]
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

let%expect_test "backend interpreter defers maps until decoding" =
  let mapped = ref 0 in
  let projection =
    let open Projection.Let_syntax in
    let%map id = Projection.expr (Expr.param Db_type.int 7)
    and name = Projection.expr (Expr.param Db_type.text "Ada")
    and suffix = Projection.return "!" in
    Int.incr mapped;
    Int.to_string id ^ ": " ^ name ^ suffix
  in
  let compiled = compile_exn Dialect.Sqlite projection in
  let decode = Interpreter.run (B.Compiled_query.projection compiled) in
  assert (Int.equal !mapped 0);
  Stdlib.print_endline (decode ());
  assert (Int.equal !mapped 1);
  [%expect {| 7: Ada! |}]
;;
