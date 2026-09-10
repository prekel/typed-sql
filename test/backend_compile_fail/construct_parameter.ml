open! Base

let parameter (typ : int Typed_sql_backend.Db_type.t) =
  Typed_sql_backend.Db_type.Value (typ, 1)
;;
