open! Base

(* Only this test harness accepts a file at driver startup. Production drivers
   use the module emitted by codegen and never read a JSON file. *)
let () =
  let path = Stdlib.Sys.getenv "TYPED_SQL_TEST_QUERY_CACHE" in
  let channel = Stdlib.open_in_bin path in
  let source =
    Exn.protect
      ~finally:(fun () -> Stdlib.close_in channel)
      ~f:(fun () -> Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
  in
  (match Typed_sql_pgocaml_ppx.Query_cache.of_string source with
   | Ok cache -> Typed_sql_pgocaml_ppx.register_queries cache
   | Error message -> failwith message);
  Ppxlib.Driver.standalone ()
;;
