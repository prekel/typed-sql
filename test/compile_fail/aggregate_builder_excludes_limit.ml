open Typed_sql

type row

let table : row Table.t = Table.v_exn "items"
let _query = Query.Aggregate.(from table |> limit 1)
