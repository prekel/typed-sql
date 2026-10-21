open! Base

let () =
  ignore (Typed_sql_pgocaml_ppx.Query_bind.scan "SELECT 1" : (_, _) Result.t);
  Ppxlib.Driver.standalone ()
;;
