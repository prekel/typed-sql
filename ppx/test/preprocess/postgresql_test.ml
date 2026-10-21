open! Base

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      let module Q = Preprocessed_cache_queries.Concat_queries in
      let row = List.hd_exn (Q.find conn 1l) in
      assert (Int32.equal row#id 1l);
      assert (String.equal row#name "Ada");
      assert (Option.is_none row#note);
      assert (List.equal (Option.equal Int32.equal) (Q.optional conn None) []);
      assert (
        List.equal (Option.equal Int32.equal) (Q.optional conn (Some 1l)) [ Some 1l ]);
      assert (List.equal Int32.equal (Q.enums conn [ Some "happy"; None ]) [ 1l ]))
;;
