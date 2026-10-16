open! Base

let () =
  ignore (Typed_sql_ppx.Query_cache.entries : Typed_sql_ppx.Query_cache.t -> _);
  Ppxlib.Driver.standalone ()
;;
