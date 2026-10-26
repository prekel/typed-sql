open! Base
open Custom_queries.Queries

let%test_module "custom converters through local PGOCaml" =
  (module struct
    module Real_pgocaml = PGOCaml

    module PGOCaml = struct
      include (
        Real_pgocaml : module type of Real_pgocaml with type 'a t := 'a Real_pgocaml.t)

      type 'a t =
        { mutable data : 'a option
        ; mutable parameters : string option list
        ; rows : string option list list
        }

      let create rows = { data = None; parameters = []; rows }
      let bind value f = f value
      let return value = value

      let private_data conn =
        match conn.data with
        | Some data -> data
        | None -> Stdlib.raise Stdlib.Not_found
      ;;

      let set_private_data conn data = conn.data <- Some data
      let prepare _conn ~name:_ ~query:_ () = ()

      let execute_rev conn ~name:_ ~params () =
        conn.parameters <- params;
        List.rev conn.rows
      ;;
    end

    let%test_unit "local PGOCaml encodes a domain using its OCaml wrapper" =
      let conn = PGOCaml.create [ [ Some "alpha" ] ] in
      let value = Some (Typ123 "alpha") in
      let result : string option list =
        [%pgsql conn "SELECT $?value::custom_type_test.typ123"]
      in
      assert (List.equal (Option.equal String.equal) result [ Some "alpha" ]);
      assert (List.equal (Option.equal String.equal) conn.parameters [ Some "alpha" ])
    ;;

    let%test_unit "array elements use domain encoders and decoders" =
      let conn = PGOCaml.create [ [ Some "{alpha,NULL}" ] ] in
      let values = Some [ Some (Typ123 "alpha"); None ] in
      let result : value option list option list =
        [%pgsql conn "SELECT $?values::custom_type_test.typ123[]"]
      in
      assert (
        List.equal
          (Option.equal (List.equal (Option.equal equal_value)))
          result
          [ values ]);
      assert (
        List.equal (Option.equal String.equal) conn.parameters [ Some "{\"alpha\",NULL}" ])
    ;;

    let%test_unit "optional custom values preserve SQL NULL" =
      let conn = PGOCaml.create [ [ None ] ] in
      let value = None in
      let result : mood option list =
        [%pgsql conn "SELECT $?value::custom_type_test.mood123"]
      in
      assert (List.equal (Option.equal equal_mood) result [ None ]);
      assert (List.equal (Option.equal String.equal) conn.parameters [ None ])
    ;;

    let%test_unit "enum converters infer a variant instead of string" =
      let conn = PGOCaml.create [ [ Some "done" ] ] in
      let value = Some Done in
      let result : mood option list =
        [%pgsql conn "SELECT $?value::custom_type_test.mood123"]
      in
      assert (List.equal (Option.equal equal_mood) result [ Some Done ]);
      assert (List.equal (Option.equal String.equal) conn.parameters [ Some "done" ])
    ;;

    let%test_unit "opaque converters infer a custom OCaml type" =
      let conn = PGOCaml.create [ [ Some "(7,-3)" ] ] in
      let value = Some (Point123 (7, -3)) in
      let result : point option list =
        [%pgsql conn "SELECT $?value::custom_type_test.point123"]
      in
      assert (List.equal (Option.equal equal_point) result [ value ]);
      assert (List.equal (Option.equal String.equal) conn.parameters [ Some "(7,-3)" ])
    ;;

    let%test_unit "object results preserve wrapped domain elements and NULL" =
      let conn = PGOCaml.create [ [ Some "{alpha,NULL}"; None ] ] in
      let value = [ Some (Typ123 "alpha"); None ] in
      let row =
        List.hd_exn
          [%pgsql.object
            conn
              "SELECT value, optional_value FROM custom_type_test.items WHERE value = $value"]
      in
      assert (List.equal (Option.equal equal_value) row#value value);
      assert (Option.is_none row#optional_value)
    ;;
  end)
;;

let%expect_test "generated references preserve custom converter names" =
  let channel = Stdlib.open_in_bin "expanded.ml" in
  let structure =
    Exn.protect
      ~finally:(fun () -> Stdlib.close_in channel)
      ~f:(fun () -> Ppxlib.Parse.implementation (Stdlib.Lexing.from_channel channel))
  in
  let names = ref [] in
  let visitor =
    object
      inherit Ppxlib.Ast_traverse.iter as super

      method! expression expression =
        (match expression.pexp_desc with
         | Pexp_ident { txt = Ldot (Lident "PGOCaml", name); _ }
           when String.is_prefix name ~prefix:"string_of_"
                || String.is_suffix name ~suffix:"_of_string" -> names := name :: !names
         | _ -> ());
        super#expression expression
    end
  in
  visitor#structure structure;
  List.dedup_and_sort !names ~compare:String.compare |> List.iter ~f:Stdlib.print_endline;
  [%expect
    {|
    mood123_of_string
    point123_of_string
    string_of_mood123
    string_of_point123
    string_of_string
    string_of_typ123
    typ123_of_string
    |}]
;;
