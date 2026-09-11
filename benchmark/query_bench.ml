open! Base
open Typed_sql
open Infix

module Item = struct
  type row

  let table : row Table.t = Table.v_exn "items"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column

  let projection reference =
    Projection.map2
      ~f:(fun id name -> id, name)
      (Projection.expr (id reference))
      (Projection.expr (name reference))
  ;;
end

let query value =
  Query.(
    from Item.table
    |> where (fun item -> Item.name item =$ value)
    |> order_by (fun item -> Item.id item) `Asc
    |> limit 100
    |> select Item.projection)
;;

let iterations = 100_000

let () =
  let started = Unix.gettimeofday () in
  for index = 1 to iterations do
    query (Int.to_string index)
    |> Compiler.compile ~dialect:Dialect.Postgresql
    |> Stdlib.Sys.opaque_identity
    |> ignore
  done;
  let elapsed = Unix.gettimeofday () -. started in
  Stdlib.Printf.printf
    "%d query compilations in %.3fs (%.0f/s)\n"
    iterations
    elapsed
    (Float.of_int iterations /. elapsed)
;;
