open! Base
open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let nickname = Column.nullable_v_exn table "nickname" Db_type.text
end

let _ =
  Update.(
    table Person.table |> set_opt Person.nickname (Some "Ada") |> all_rows |> command)
;;
