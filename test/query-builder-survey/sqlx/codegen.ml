open! Base
module C = Typed_sql_ppx_cache.Query_cache

let () =
  let channel = Stdlib.open_in_bin Stdlib.Sys.argv.(1) in
  let source =
    Exn.protect
      ~finally:(fun () -> Stdlib.close_in channel)
      ~f:(fun () -> Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
  in
  match C.of_string source with
  | Ok cache -> Stdlib.print_string (C.codegen ~target:`Typed_sql_ppx cache)
  | Error message -> failwith message
;;
