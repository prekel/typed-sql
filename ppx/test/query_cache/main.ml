open! Base

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      let module Q = Cache_queries in
      Q.insert conn ~id:2l ~name:"Grace" ~mood:"sad" ~tag:20l ~nums:[ Some 2l; None ];
      let row = List.hd_exn (Q.find conn 2l) in
      assert (Int32.equal row#id 2l);
      assert (String.equal row#name "Grace");
      assert (Option.is_none row#note);
      assert (String.equal row#mood "sad");
      assert (Int32.equal row#tag 20l);
      assert (List.equal (Option.equal Int32.equal) row#nums [ Some 2l; None ]);
      assert (
        List.equal
          (Option.equal String.equal)
          (Q.update conn ~id:2l ~note:(Some "updated"))
          [ Some "updated" ]);
      assert (List.equal Int32.equal (Q.enums conn [ Some "happy"; None ]) [ 1l ]);
      assert (
        List.equal
          (Option.equal Int64.equal)
          (Q.grouped conn)
          [ Some 1L; Some 1L; Some 2L ]);
      assert (
        List.equal (Option.equal String.equal) (Q.regex conn "[0-9]+") [ Some "123" ]);
      assert (
        List.equal (Option.equal Int32.equal) (Q.optional conn (Some 1l)) [ Some 1l ]);
      assert (List.equal (Option.equal Int32.equal) (Q.expression conn 3l) [ Some 4l ]);
      assert (List.for_all (Q.left_join conn) ~f:(fun row -> Option.is_none row#missing));
      Q.remove conn 2l)
;;
