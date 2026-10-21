open! Base

let equal_inet (left, left_mask) (right, right_mask) =
  String.equal (Unix.string_of_inet_addr left) (Unix.string_of_inet_addr right)
  && Int.equal left_mask right_mask
;;

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      let module Q = Inet_queries.Queries in
      let addresses =
        List.map
          [ "192.0.2.129/24"; "192.0.2.1"; "2001:db8::1234/64"; "::1" ]
          ~f:PGOCaml.inet_of_string
      in
      List.iter (None :: List.map addresses ~f:Option.some) ~f:(fun address ->
        assert (List.equal (Option.equal equal_inet) (Q.scalar conn address) [ address ]));
      let array_values = List.map addresses ~f:Option.some @ [ None ] in
      List.iter [ None; Some []; Some array_values ] ~f:(fun values ->
        assert (
          List.equal
            (Option.equal (List.equal (Option.equal equal_inet)))
            (Q.array conn values)
            [ values ]));
      List.iter (None :: List.map addresses ~f:Option.some) ~f:(fun address ->
        assert (List.equal (Option.equal equal_inet) (Q.domain conn address) [ address ]));
      let address = PGOCaml.inet_of_string "192.0.2.129/24" in
      let row = List.hd_exn (Q.object_row conn address) in
      assert (equal_inet row#address address);
      assert (Option.is_none row#optional_address))
;;
