open! Base

let () =
  ignore (Typed_sql_pgocaml_ppx.Sql.parse "" : (_, _) Result.t);
  Ppxlib.Driver.standalone ()
;;
