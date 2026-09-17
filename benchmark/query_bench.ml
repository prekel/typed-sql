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

let small_query value =
  Query.(
    from Item.table
    |> where (fun item -> Item.name item =$ value)
    |> order_by (fun item -> Item.id item) `Asc
    |> limit 100
    |> select Item.projection)
;;

let filtered_query ~conditions value =
  let builder =
    List.fold
      (List.range 0 conditions)
      ~init:Query.(from Item.table)
      ~f:(fun query index ->
        Query.(
          query
          |> where (fun item ->
            Item.id item >$ Int64.of_int index &&. (Item.name item <>$ value))))
  in
  Query.(builder |> select Item.projection)
;;

let ordered_query ~orders =
  let builder =
    List.fold
      (List.range 0 orders)
      ~init:Query.(from Item.table)
      ~f:(fun query index ->
        let direction =
          if Int.(index % 2 = 0) then
            `Asc
          else
            `Desc
        in
        Query.(query |> order_by Item.id direction))
  in
  Query.(builder |> select Item.projection)
;;

let compile query =
  Statement.For_dialect.query_many ~dialect:Dialect.postgresql (fun _ -> query)
  |> Result.map_error ~f:(fun (error : Statement.definition_error) ->
    Compile_error.to_string error.error)
  |> Result.ok_or_failwith
  |> Stdlib.Sys.opaque_identity
  |> ignore
;;

let measure ~name ~iterations make_query =
  Stdlib.Gc.full_major ();
  let started = Unix.gettimeofday () in
  for index = 1 to iterations do
    make_query index |> compile
  done;
  let elapsed = Unix.gettimeofday () -. started in
  Stdlib.Printf.printf
    "%-28s %7d iterations in %.3fs (%9.0f/s)\n"
    name
    iterations
    elapsed
    (Float.of_int iterations /. elapsed)
;;

let () =
  measure ~name:"small" ~iterations:100_000 (fun index ->
    small_query (Int.to_string index));
  measure ~name:"20 WHERE conditions" ~iterations:10_000 (fun index ->
    filtered_query ~conditions:20 (Int.to_string index));
  measure ~name:"100 WHERE conditions" ~iterations:2_000 (fun index ->
    filtered_query ~conditions:100 (Int.to_string index));
  measure ~name:"20 ORDER BY expressions" ~iterations:20_000 (fun _ ->
    ordered_query ~orders:20);
  measure ~name:"100 ORDER BY expressions" ~iterations:5_000 (fun _ ->
    ordered_query ~orders:100)
;;
