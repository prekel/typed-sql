open! Base
open Custom_queries.Queries

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      List.iter [ None; Some (Typ123 "alpha") ] ~f:(fun value ->
        assert (
          List.equal
            (Option.equal String.equal)
            (domain conn value)
            [ Option.map value ~f:PGOCaml.string_of_typ123 ]));
      let values =
        [ None
        ; Some []
        ; Some
            [ Some (Typ123 "alpha"); None; Some (Typ123 "NULL"); Some (Typ123 "a\"\\b") ]
        ]
      in
      List.iter values ~f:(fun values ->
        assert (
          List.equal
            (Option.equal (List.equal (Option.equal equal_value)))
            (array conn values)
            [ values ]));
      List.iter [ None; Some Ready; Some Done ] ~f:(fun value ->
        assert (List.equal (Option.equal equal_mood) (enum conn value) [ value ]));
      List.iter
        [ None; Some (Point123 (7, -3)) ]
        ~f:(fun value ->
          assert (List.equal (Option.equal equal_point) (composite conn value) [ value ]));
      let value = [ Some (Typ123 "alpha"); None ] in
      let row = List.hd_exn (object_row conn value) in
      assert (List.equal (Option.equal equal_value) row#value value);
      assert (Option.is_none row#optional_value))
;;
