open! Base

let () =
  let conn = PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") () in
  Exn.protect
    ~finally:(fun () -> PGOCaml.close conn)
    ~f:(fun () ->
      let real = 42l in
      let rows : (string option * string option * string option * int32 option) list =
        [%pgsql
          conn
            {sql|SELECT E'\n\r\t\b\f\\\047\x41\u00e9\U0001f600',
          $tag$$?fake -- $id /* */ 'quote' $other$$tag$,
          $$ $@list $$, $real::integer|sql}]
      in
      match rows with
      | [ (a, b, c, d) ] ->
        assert (Option.equal String.equal a (Some "\n\r\t\b\012\\'Aé😀"));
        assert (Option.equal String.equal b (Some "$?fake -- $id /* */ 'quote' $other$"));
        assert (Option.equal String.equal c (Some " $@list "));
        assert (Option.equal Int32.equal d (Some real))
      | _ -> failwith "expected one literal row")
;;
