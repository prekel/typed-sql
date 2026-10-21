open! Base

let () =
  ignore (Query_concat_test_ppx.Concat.preprocess_impl : Ppxlib.structure -> _);
  ignore (Typed_sql_pgocaml_ppx.Query_bind.scan "SELECT 1" : (_, _) Result.t);
  Ppxlib.Driver.standalone ()
;;
