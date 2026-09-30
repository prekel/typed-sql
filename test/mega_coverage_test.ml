open! Base
open Typed_sql
open Infix

let mapped_text_type : string Db_type.t =
  Db_type.map
    ~name:"mega_text"
    ~encode:(fun value -> Ok value)
    ~decode:(fun value -> Ok value)
    Db_type.text
;;

module Person = struct
  type row

  let table : row Table.t = Table.v_exn ~schema:"public" "mega_people"
  let id_column = Column.v_exn table "id" Db_type.int64
  let name_column = Column.v_exn table "name" Db_type.text
  let score_column = Column.v_exn table "score" Db_type.int64
  let nickname_column = Column.nullable_v_exn table "nickname" Db_type.text
  let bio_column = Column.nullable_v_exn table "bio" Db_type.text
  let status_column = Column.v_exn table "status" Db_type.text
  let active_column = Column.v_exn table "active" Db_type.bool
  let id reference = Expr.column reference id_column
  let name reference = Expr.column reference name_column
  let score reference = Expr.column reference score_column
  let nickname reference = Expr.column reference nickname_column
  let projection reference = Projection.pair (id reference) (name reference)
end

module Expired = struct
  type row

  let table : row Table.t = Table.v_exn "mega_expired"
  let id_column = Column.v_exn table "id" Db_type.int64
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let score_column = Column.v_exn table "score" Db_type.int
  let id reference = Expr.column reference id_column
  let person_id reference = Expr.column reference person_id_column
  let label reference = Expr.column reference label_column
  let score reference = Expr.column reference score_column

  let projection reference =
    Projection.both
      (Projection.pair (id reference) (person_id reference))
      (Projection.pair (label reference) (score reference))
  ;;
end

module Deleted = struct
  type row

  let table : row Table.t = Table.v_exn "mega_deleted_rows"
  let id_column = Column.v_exn table "id" Db_type.int64
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let score_column = Column.v_exn table "score" Db_type.int
  let id reference = Expr.column reference id_column
  let person_id reference = Expr.column reference person_id_column
  let label reference = Expr.column reference label_column
  let score reference = Expr.column reference score_column

  let projection reference =
    Projection.both
      (Projection.pair (id reference) (person_id reference))
      (Projection.pair (label reference) (score reference))
  ;;
end

module Archive = struct
  type row

  let table : row Table.t = Table.v_exn "mega_archive"
  let id_column = Column.v_exn table "id" Db_type.int64
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let score_column = Column.v_exn table "score" Db_type.int
  let id reference = Expr.column reference id_column
  let person_id reference = Expr.column reference person_id_column
  let label reference = Expr.column reference label_column
  let score reference = Expr.column reference score_column

  let projection reference =
    Projection.both
      (Projection.pair (id reference) (person_id reference))
      (Projection.pair (label reference) (score reference))
  ;;
end

module Updated = struct
  type row

  let table : row Table.t = Table.v_exn "mega_updated_rows"
  let id_column = Column.v_exn table "id" Db_type.int64
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let score_column = Column.v_exn table "score" Db_type.int
  let id reference = Expr.column reference id_column
  let person_id reference = Expr.column reference person_id_column
  let label reference = Expr.column reference label_column
  let score reference = Expr.column reference score_column

  let projection reference =
    Projection.both
      (Projection.pair (id reference) (person_id reference))
      (Projection.pair (label reference) (score reference))
  ;;
end

module Audit = struct
  type row

  let table : row Table.t = Table.v_exn "mega_audit"
  let id_column = Column.v_exn table "id" Db_type.int64
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let score_column = Column.v_exn table "score" Db_type.int
  let id reference = Expr.column reference id_column
  let person_id reference = Expr.column reference person_id_column
  let nullable_id reference = Expr.nullable_column reference id_column
  let label reference = Expr.column reference label_column
  let score reference = Expr.column reference score_column

  let projection reference =
    Projection.both
      (Projection.pair (id reference) (person_id reference))
      (Projection.pair (label reference) (score reference))
  ;;
end

module Combined = struct
  type row

  let table : row Table.t = Table.v_exn "mega_combined_rows"
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let score_column = Column.v_exn table "score" Db_type.int
  let person_id reference = Expr.column reference person_id_column
  let score reference = Expr.column reference score_column
  let projection reference = Projection.pair (person_id reference) (score reference)
end

module Summary = struct
  type row

  let table : row Table.t = Table.v_exn "mega_summary"
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let event_count_column = Column.v_exn table "event_count" Db_type.int64
  let total_score_column = Column.nullable_v_exn table "total_score" Db_type.int64
  let person_id reference = Expr.column reference person_id_column
  let event_count reference = Expr.column reference event_count_column
  let total_score reference = Expr.column reference total_score_column

  let projection reference =
    Projection.map3
      ~f:(fun person_id event_count total_score -> person_id, event_count, total_score)
      (Projection.expr (person_id reference))
      (Projection.expr (event_count reference))
      (Projection.expr (total_score reference))
  ;;
end

module Sequence = struct
  type row

  let table : row Table.t = Table.v_exn "mega_sequence"
  let value_column = Column.v_exn table "value" Db_type.int64
  let value reference = Expr.column reference value_column
  let projection reference = Projection.expr (value reference)
end

module Event = struct
  type row

  let table : row Table.t = Table.v_exn "mega_events"
  let id_column = Column.v_exn table "id" Db_type.int64
  let person_id_column = Column.v_exn table "person_id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let nullable_label_column = Column.nullable_v_exn table "nullable_label" Db_type.text
  let mapped_label_column = Column.nullable_v_exn table "mapped_label" mapped_text_type
  let date_column = Column.v_exn table "happened_on" Db_type.date
  let uuid_column = Column.v_exn table "external_id" Db_type.uuid
  let value_column = Column.v_exn table "value" Db_type.int
  let nullable_value_column = Column.nullable_v_exn table "nullable_value" Db_type.int
  let float_value_column = Column.v_exn table "float_value" Db_type.float

  let nullable_float_value_column =
    Column.nullable_v_exn table "nullable_float_value" Db_type.float
  ;;

  let nullable_id_column = Column.nullable_v_exn table "nullable_id" Db_type.int64
  let numeric_value_column = Column.v_exn table "numeric_value" Db_type.numeric

  let nullable_numeric_value_column =
    Column.nullable_v_exn table "nullable_numeric_value" Db_type.numeric
  ;;

  let id reference = Expr.column reference id_column
  let person_id reference = Expr.column reference person_id_column
  let label reference = Expr.column reference label_column
  let nullable_label reference = Expr.column reference nullable_label_column
  let mapped_label reference = Expr.column reference mapped_label_column
  let happened_on reference = Expr.column reference date_column
  let external_id reference = Expr.column reference uuid_column
  let value reference = Expr.column reference value_column
  let nullable_value reference = Expr.column reference nullable_value_column
  let float_value reference = Expr.column reference float_value_column
  let nullable_float_value reference = Expr.column reference nullable_float_value_column
  let nullable_id reference = Expr.column reference nullable_id_column
  let numeric_value reference = Expr.column reference numeric_value_column

  let nullable_numeric_value reference =
    Expr.column reference nullable_numeric_value_column
  ;;

  let projection reference =
    Projection.both
      (Projection.pair (id reference) (person_id reference))
      (Projection.expr (label reference))
  ;;
end

module Aggregate_metrics = struct
  type row

  let table : row Table.t = Table.v_exn "mega_aggregate_metrics"
  let count_all_column = Column.v_exn table "count_all" Db_type.int64
  let count_id_column = Column.v_exn table "count_id" Db_type.int64
  let count_distinct_column = Column.v_exn table "count_distinct" Db_type.int64
  let sum_int_column = Column.nullable_v_exn table "sum_int" Db_type.int64

  let sum_nullable_int_column =
    Column.nullable_v_exn table "sum_nullable_int" Db_type.int64
  ;;

  let sum_float_column = Column.nullable_v_exn table "sum_float" Db_type.float

  let sum_nullable_float_column =
    Column.nullable_v_exn table "sum_nullable_float" Db_type.float
  ;;

  let min_text_column = Column.nullable_v_exn table "min_text" Db_type.text
  let max_text_column = Column.nullable_v_exn table "max_text" Db_type.text

  let min_nullable_text_column =
    Column.nullable_v_exn table "min_nullable_text" Db_type.text
  ;;

  let max_nullable_text_column =
    Column.nullable_v_exn table "max_nullable_text" Db_type.text
  ;;

  let sum_int64_column = Column.nullable_v_exn table "sum_int64" Db_type.numeric

  let sum_nullable_int64_column =
    Column.nullable_v_exn table "sum_nullable_int64" Db_type.numeric
  ;;

  let sum_numeric_column = Column.nullable_v_exn table "sum_numeric" Db_type.numeric

  let sum_nullable_numeric_column =
    Column.nullable_v_exn table "sum_nullable_numeric" Db_type.numeric
  ;;

  let min_numeric_column = Column.nullable_v_exn table "min_numeric" Db_type.numeric
  let max_numeric_column = Column.nullable_v_exn table "max_numeric" Db_type.numeric

  let min_nullable_numeric_column =
    Column.nullable_v_exn table "min_nullable_numeric" Db_type.numeric
  ;;

  let max_nullable_numeric_column =
    Column.nullable_v_exn table "max_nullable_numeric" Db_type.numeric
  ;;

  let count_all reference = Expr.column reference count_all_column

  let projection reference =
    let field column = Projection.expr (Expr.column reference column) in
    let counts =
      Projection.both
        (field count_all_column)
        (Projection.both (field count_id_column) (field count_distinct_column))
    in
    let sums =
      Projection.both
        (field sum_int_column)
        (Projection.both
           (field sum_nullable_int_column)
           (Projection.both (field sum_float_column) (field sum_nullable_float_column)))
    in
    let text_extrema =
      Projection.both
        (field min_text_column)
        (Projection.both
           (field max_text_column)
           (Projection.both
              (field min_nullable_text_column)
              (field max_nullable_text_column)))
    in
    let numeric_sums =
      Projection.both
        (field sum_int64_column)
        (Projection.both
           (field sum_nullable_int64_column)
           (Projection.both
              (field sum_numeric_column)
              (field sum_nullable_numeric_column)))
    in
    let numeric_extrema =
      Projection.both
        (field min_numeric_column)
        (Projection.both
           (field max_numeric_column)
           (Projection.both
              (field min_nullable_numeric_column)
              (field max_nullable_numeric_column)))
    in
    Projection.both
      counts
      (Projection.both
         sums
         (Projection.both text_extrema (Projection.both numeric_sums numeric_extrema)))
  ;;
end

module Tag = struct
  type row

  let table : row Table.t = Table.v_exn "mega_tags"
  let id_column = Column.v_exn table "id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let id reference = Expr.column reference id_column
  let label reference = Expr.column reference label_column
  let projection reference = Projection.pair (id reference) (label reference)
end

module Input_rows = struct
  type row

  let table : row Table.t = Table.v_exn "mega_input_rows"
  let id_column = Column.v_exn table "id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let id reference = Expr.column reference id_column
  let label reference = Expr.column reference label_column
  let projection reference = Projection.pair (id reference) (label reference)
end

module Cleanup = struct
  type row

  let table : row Table.t = Table.v_exn "mega_cleanup"
end

module Maintenance = struct
  type row

  let table : row Table.t = Table.v_exn "mega_maintenance"
  let enabled_column = Column.v_exn table "enabled" Db_type.bool
end

module Outbox = struct
  type row

  let table : row Table.t = Table.v_exn "mega_outbox"
  let id_column = Column.v_exn table "id" Db_type.int64
  let label_column = Column.v_exn table "label" Db_type.text
  let id reference = Expr.column reference id_column
  let label reference = Expr.column reference label_column
  let projection reference = Projection.pair (id reference) (label reference)
end

let selected_tags : (Tag.row, Dialect.postgresql) Values.t =
  Values.create_dynamic
    ~table:Tag.table
    ~columns:Tag.projection
    ~rows:
      [ [ Values.Cell.expr (Expr.constant Db_type.int64 1L)
        ; Values.Cell.expr (Expr.constant Db_type.text "one")
        ]
      ; [ Values.Cell.expr (Expr.constant Db_type.int64 2L)
        ; Values.Cell.expr (Expr.constant Db_type.text "two")
        ]
      ]
;;

let static_tags : (Tag.row, Dialect.postgresql) Values.t =
  Values.create
    ~table:Tag.table
    ~columns:Tag.projection
    ~first:
      (Values.Row.pair
         (Expr.constant Db_type.int64 1L)
         (Expr.constant Db_type.text "one"))
    ~rest:
      [ Values.Row.pair
          (Expr.constant Db_type.int64 2L)
          (Expr.constant Db_type.text "two")
      ]
;;

let inferred_people : (_, _, Dialect.postgresql) Derived_table.inferred =
  Query.(
    from Person.table
    |> select_relation (fun person ->
      Derived_table.Fields.pair (Person.id person) (Person.score person)))
;;

let input_rows_query ~limit_parameter ~offset_parameter =
  let inferred_branch =
    Query.(
      from_relation inferred_people
      |> inner_join_values selected_tags ~on:(fun (person_id, _) tag ->
        person_id =. Tag.id tag)
      |> left_join_values selected_tags ~on:(fun ((person_id, _), _) tag ->
        person_id =. Tag.id tag)
      |> where_opt None ~f:(fun _ _ -> Condition.true_)
      |> where_opt (Some 0L) ~f:(fun (((person_id, _), _), _) minimum ->
        person_id >$ minimum)
      |> where_optional_param
           (Expr.to_nullable (Expr.constant Db_type.int64 0L))
           ~f:(fun _ parameter -> Expr.is_not_null parameter)
      |> distinct
      |> order_by (fun (((person_id, _), _), _) -> person_id) `Asc
      |> offset_param offset_parameter
      |> limit_param limit_parameter
      |> select (fun (((person_id, _), tag), _) ->
        Projection.pair person_id (Expr.lower (Tag.label tag))))
  in
  let values_branch = Query.(from_values static_tags |> select Tag.projection) in
  Query.union_all
    ~order_by:[ Identifier.of_string_exn "field_1", `Asc ]
    inferred_branch
    values_branch
;;

let input_rows_relation ~limit_parameter ~offset_parameter
  : (Input_rows.row, Dialect.postgresql) Derived_table.t
  =
  Derived_table.create
    ~table:Input_rows.table
    ~columns:Input_rows.projection
    (input_rows_query ~limit_parameter ~offset_parameter)
;;

let event_relation : (Event.row, Dialect.postgresql) Derived_table.t =
  Derived_table.create
    ~table:Event.table
    ~columns:Event.projection
    Query.(from Event.table |> select Event.projection)
;;

let joined_event_query =
  Query.(
    from_derived event_relation
    |> inner_join_derived event_relation ~on:(fun first second ->
      Event.id first =. Event.id second)
    |> left_join_derived event_relation ~on:(fun (first, _) third ->
      Event.id first =. Event.id third)
    |> inner_join Event.table ~on:(fun ((first, _), _) second ->
      Event.id first =. Event.id second)
    |> left_join Event.table ~on:(fun (((first, _), _), _) third ->
      Event.id first =. Event.id third)
    |> select (fun ((((first, _), _), _), _) -> Event.projection first))
;;

let joined_events =
  Cte.select
    (Derived_table.create ~table:Event.table ~columns:Event.projection joined_event_query)
;;

let outbox_insert =
  Insert.(
    rows
      Outbox.table
      [ (fun row ->
          row |> set Outbox.id_column 101L |> set Outbox.label_column "inserted")
      ; (fun row ->
          row |> set Outbox.label_column "also inserted" |> set Outbox.id_column 102L)
      ]
    |> on_conflict_do_nothing
    |> returning Outbox.projection)
;;

let outbox_rows =
  Postgresql.Cte.returning ~table:Outbox.table ~columns:Outbox.projection outbox_insert
;;

let aggregate_query =
  Query.Aggregate.(from Event.table |> where (fun event -> Event.id event >$ 0L))
  |> Query.aggregate_one (fun event ->
    let open Aggregate_projection.Let_syntax in
    let%map count_all = Aggregate_projection.count_all
    and count_id = Aggregate_projection.count (Event.id event)
    and count_distinct = Aggregate_projection.count_distinct (Event.person_id event)
    and sum_int = Aggregate_projection.sum_int (Event.value event)
    and sum_nullable_int =
      Aggregate_projection.sum_int_nullable (Event.nullable_value event)
    and sum_float = Aggregate_projection.sum_float (Event.float_value event)
    and sum_nullable_float =
      Aggregate_projection.sum_float_nullable (Event.nullable_float_value event)
    and min_text = Aggregate_projection.min Db_type.Orderable.text (Event.label event)
    and max_text = Aggregate_projection.max Db_type.Orderable.text (Event.label event)
    and min_nullable_text =
      Aggregate_projection.min_nullable
        Db_type.Orderable.text
        (Event.nullable_label event)
    and max_nullable_text =
      Aggregate_projection.max_nullable
        Db_type.Orderable.text
        (Event.nullable_label event)
    and sum_int64 = Postgresql.Numeric_projection.sum_int64 (Event.id event)
    and sum_nullable_int64 =
      Postgresql.Numeric_projection.sum_int64_nullable (Event.nullable_id event)
    and sum_numeric =
      Postgresql.Numeric_projection.sum_numeric (Event.numeric_value event)
    and sum_nullable_numeric =
      Postgresql.Numeric_projection.sum_numeric_nullable
        (Event.nullable_numeric_value event)
    and min_numeric =
      Postgresql.Numeric_projection.min_numeric (Event.numeric_value event)
    and max_numeric =
      Postgresql.Numeric_projection.max_numeric (Event.numeric_value event)
    and min_nullable_numeric =
      Postgresql.Numeric_projection.min_numeric_nullable
        (Event.nullable_numeric_value event)
    and max_nullable_numeric =
      Postgresql.Numeric_projection.max_numeric_nullable
        (Event.nullable_numeric_value event)
    in
    ( count_all
    , count_id
    , count_distinct
    , sum_int
    , sum_nullable_int
    , sum_float
    , sum_nullable_float
    , min_text
    , max_text
    , min_nullable_text
    , max_nullable_text
    , sum_int64
    , sum_nullable_int64
    , sum_numeric
    , sum_nullable_numeric
    , min_numeric
    , max_numeric
    , min_nullable_numeric
    , max_nullable_numeric ))
;;

let aggregate_metrics =
  Cte.select
    (Derived_table.create
       ~table:Aggregate_metrics.table
       ~columns:Aggregate_metrics.projection
       aggregate_query)
;;

let calendar_date = Date.of_ymd_exn ~year:2026 ~month:9 ~day:30
let external_uuid = Uuid.of_string_exn "550e8400-e29b-41d4-a716-446655440000"
let exact_amount = Decimal.of_string "12.3400e-2" |> Option.value_exn

let is_not_null_parameter db_type value =
  Expr.is_not_null (Expr.to_nullable (Expr.constant db_type value))
;;

let delete_expired =
  Delete.(
    from Expired.table
    |> where (fun expired -> Expired.score expired <$ 0)
    |> returning Expired.projection)
;;

let deleted_rows =
  Postgresql.Cte.returning ~table:Deleted.table ~columns:Deleted.projection delete_expired
;;

let sequence_relation query =
  Derived_table.create ~table:Sequence.table ~columns:Sequence.projection query
;;

let recursive_sequence =
  Cte.recursive
    ~union:`Union_all
    ~anchor:
      (sequence_relation
         (let one = Expr.constant Db_type.int64 1L in
          Query.union (Query.select_one one) (Query.select_one Expr.count_all)))
    ~step:(fun sequence ->
      sequence_relation
        Query.(
          from_cte sequence
          |> where (fun number -> Sequence.value number <$ 4L)
          |> select (fun number ->
            Projection.expr
              Expr.Int64.Infix.(Sequence.value number +. Expr.constant Db_type.int64 1L))))
;;

let cleanup_effect =
  Postgresql.Cte.command Delete.(from Cleanup.table |> all_rows |> command)
;;

let maintenance_effect =
  Postgresql.Cte.command
    Update.(
      table Maintenance.table
      |> set Maintenance.enabled_column true
      |> all_rows
      |> command)
;;

let final_update
      ~sequence
      ~inputs
      ~input_rows_relation
      ~label_parameter
      ~joined_events
      ~metrics
      ~outbox
      ~summary
  =
  Update.(
    table Person.table
    |> from Event.table ~f:(fun person event update ->
      update
      |> from_derived input_rows_relation ~f:(fun person input update ->
        update
        |> from_relation inferred_people ~f:(fun person (inferred_person_id, _) update ->
          update
          |> from_cte summary ~f:(fun person totals update ->
            let event_count =
              Query.(
                from Event.table
                |> where (fun event -> Event.person_id event =. Person.id person)
                |> select_scalar (fun _ -> Expr.count_all))
              |> Expr.scalar_subquery
              |> fun count ->
              Expr.coalesce count ~default:(Expr.constant Db_type.int64 0L)
            in
            let first_event_person_id =
              Query.(
                from Event.table
                |> where (fun event -> Event.person_id event =. Person.id person)
                |> limit_one
                |> select_scalar Event.person_id)
            in
            let has_sequence_value =
              Query.(
                from_cte sequence
                |> where (fun number -> Sequence.value number =. Person.id person)
                |> exists_expr)
            in
            let has_related_event =
              Query.(
                from Event.table
                |> where (fun event -> Event.person_id event =. Person.id person)
                |> exists_expr)
            in
            let has_input_row =
              Query.(
                from_cte inputs
                |> where (fun input -> Input_rows.id input =. Person.id person)
                |> exists_expr)
            in
            let has_rejoined_inferred_people =
              Query.(
                from_relation inferred_people
                |> inner_join_relation
                     inferred_people
                     ~on:(fun (person_id, _) (joined_id, _) -> person_id =. joined_id)
                |> left_join_relation
                     inferred_people
                     ~on:(fun ((person_id, _), _) (joined_id, _) ->
                       person_id =. joined_id)
                |> exists_expr)
            in
            let has_joined_event =
              Query.(
                from_cte joined_events
                |> inner_join_cte joined_events ~on:(fun event joined ->
                  Event.id event =. Event.id joined)
                |> where (fun (event, _) -> Event.person_id event =. Person.id person)
                |> exists_expr)
            in
            let has_aggregate_metrics =
              Query.(
                from_cte metrics
                |> where (fun row -> Aggregate_metrics.count_all row >$ 0L)
                |> exists_expr)
            in
            let has_outbox_rows =
              Query.(
                from_cte outbox |> where (fun row -> Outbox.id row >$ 0L) |> exists_expr)
            in
            let no_future_event =
              Query.(
                from Event.table
                |> where (fun event -> Event.person_id event >. Person.id person)
                |> not_exists)
            in
            let updated_name =
              Expr.case
                [ Summary.event_count totals >$ 1L, Expr.upper (Person.name person) ]
                ~else_:(Expr.lower (Person.name person))
              |> fun name -> Expr.concat_value name "!"
            in
            update
            |> set Person.active_column true
            |> set_opt Person.nickname_column (Some None)
            |> set_expr_opt
                 Person.bio_column
                 (Some (Expr.to_nullable (Expr.constant Db_type.text "updated")))
            |> default Person.status_column
            |> set_expr
                 Person.score_column
                 Expr.Int64.Infix.(
                   Person.score person
                   +. Expr.coalesce
                        (Summary.total_score totals)
                        ~default:(Expr.constant Db_type.int64 0L))
            |> set_expr Person.name_column updated_name
            |> where (fun _ ->
              Person.id person
              =. Summary.person_id totals
              &&. is_not_null_parameter Db_type.bool true
              &&. is_not_null_parameter Db_type.int 1
              &&. is_not_null_parameter Db_type.int64 1L
              &&. is_not_null_parameter Db_type.float 1.5
              &&. is_not_null_parameter Db_type.numeric exact_amount
              &&. Expr.is_not_null (Expr.to_nullable label_parameter)
              &&. is_not_null_parameter Db_type.bytes (Bytes.of_string "mega")
              &&. is_not_null_parameter Db_type.date calendar_date
              &&. is_not_null_parameter Db_type.timestamp Ptime.epoch
              &&. is_not_null_parameter Db_type.uuid external_uuid
              &&. Expr.is_not_null
                    (Expr.constant (Db_type.option mapped_text_type) (Some "mapped"))
              &&. (Event.person_id event =. Person.id person)
              &&. (Input_rows.id input =. Person.id person)
              &&. (inferred_person_id =. Person.id person)
              &&. Expr.is_distinct_from (Person.name person) label_parameter
              &&. (has_sequence_value =$ true)
              &&. (has_related_event =$ true)
              &&. (has_input_row =$ true)
              &&. (has_rejoined_inferred_people =$ true)
              &&. (has_joined_event =$ true)
              &&. (has_aggregate_metrics =$ true)
              &&. (has_outbox_rows =$ true)
              &&. (event_count >$ 0L)
              &&. Expr.in_ (Person.id person) [ 1L; 2L ]
              &&. Expr.not_in (Person.id person) [ -1L ]
              &&. Expr.in_exprs
                    (Person.name person)
                    [ Expr.constant Db_type.text "Ada"
                    ; Expr.constant Db_type.text "Edsger"
                    ]
              &&. Expr.not_in_exprs
                    (Person.name person)
                    [ Expr.constant Db_type.text "unknown" ]
              &&. Expr.between (Person.score person) ~lower:0L ~upper:1000L
              &&. Condition.not_ (Expr.is_null (Person.nickname person))
              &&. no_future_event
              &&. Query.in_subquery (Person.id person) first_event_person_id)))))
    |> returning (fun person ->
      let related_events =
        Query.(
          from Event.table
          |> where (fun event -> Event.person_id event =. Person.id person)
          |> order_by (fun event -> Event.id event) `Asc
          |> limit 5
          |> select Event.projection)
      in
      let aggregate_events =
        Query.(
          from Event.table
          |> select_exactly_one (fun event ->
            let has_positive_event =
              Query.(
                from Event.table
                |> where (fun nested ->
                  Event.person_id nested =. Person.id person &&. (Event.value nested >$ 0))
                |> exists_expr)
            in
            let filter =
              Event.person_id event =. Person.id person &&. (has_positive_event =$ true)
            in
            let nested_events =
              Query.(
                from Event.table
                |> where (fun nested -> Event.person_id nested =. Person.id person)
                |> select (fun nested -> Projection.expr (Event.id nested)))
            in
            let typed_scalar_metadata =
              Projection.both
                (Projection.expr (Event.happened_on event))
                (Projection.both
                   (Projection.expr (Event.external_id event))
                   (Projection.expr (Event.mapped_label event)))
            in
            let event_and_nested =
              Projection.both (Event.projection event) (Query.multiset nested_events)
            in
            Projection.multiset_agg
              ~filter
              ~order_by:[ Aggregate_order.asc (Event.id event) ]
              (Projection.both event_and_nested typed_scalar_metadata)))
      in
      let aggregate_analysis =
        Query.(
          from Event.table
          |> select_scalar (fun event ->
            let scalar_id =
              Query.(
                from Event.table
                |> where (fun nested -> Event.id nested =. Event.id event)
                |> limit_one
                |> select_scalar Event.id)
            in
            let nullable_scalar_id =
              Query.(
                from Event.table
                |> where (fun nested -> Event.id nested =. Event.id event)
                |> limit_one
                |> select_scalar Event.nullable_id)
            in
            let related_events =
              Query.(
                from Event.table
                |> where (fun nested -> Event.person_id nested =. Event.person_id event))
            in
            let compound_condition =
              Event.id event
              =. Expr.Int64.Infix.(Event.id event +. Expr.constant Db_type.int64 1L)
              &&. (Expr.Int64.Infix.(Event.id event -. Expr.constant Db_type.int64 1L)
                   =. Expr.constant Db_type.int64 9L)
              &&. (Expr.Int64.Infix.(Event.id event *. Expr.constant Db_type.int64 1L)
                   =. Event.id event)
              &&. (Expr.Int64.Infix.(Event.id event /. Expr.constant Db_type.int64 1L)
                   =. Event.id event)
              &&. (Event.id event <>. Expr.constant Db_type.int64 0L)
              &&. (Event.id event <>$ 0L)
              &&. (Event.id event <. Expr.constant Db_type.int64 100L)
              &&. (Event.id event <=. Expr.constant Db_type.int64 100L)
              &&. (Event.id event >=. Expr.constant Db_type.int64 0L)
              &&. (Event.id event <=$ 100L)
              &&. (Event.id event >=$ 0L)
              &&. Expr.is_null (Event.nullable_id event)
              &&. Expr.is_not_null (Event.nullable_id event)
              &&. Expr.in_ (Event.id event) [ 1L; 2L ]
              &&. Expr.not_in (Event.id event) [ -1L ]
              &&. Expr.in_exprs (Event.id event) [ Expr.constant Db_type.int64 3L ]
              &&. Expr.not_in_exprs (Event.id event) [ Expr.constant Db_type.int64 4L ]
              &&. Expr.between (Event.id event) ~lower:0L ~upper:100L
              &&. Query.in_subquery (Event.id event) scalar_id
              &&. Query.not_in_subquery (Event.id event) scalar_id
              &&. Query.exists related_events
              &&. Query.not_exists related_events
              &&. Expr.is_distinct_from_value (Event.label event) "different"
              &&. (Event.label event =~. Expr.constant Db_type.text "%v%")
              &&. (Expr.length (Event.label event) >$ 0)
              &&. (Expr.scalar_subquery_nullable nullable_scalar_id
                   =. Expr.to_nullable (Event.id event))
              &&. Condition.not_ (Event.id event >$ 0L)
              &&. (Expr.concat_value (Expr.lower (Event.label event)) "x" =~$ "%")
              &&. (Expr.coalesce
                     (Event.nullable_id event)
                     ~default:(Expr.constant Db_type.int64 0L)
                   >$ 0L)
              &&. (Expr.case
                     [ Condition.true_, Event.id event ]
                     ~else_:(Expr.constant Db_type.int64 0L)
                   >$ 0L)
              &&. (Expr.current_timestamp =. Expr.current_timestamp)
            in
            Expr.coalesce
              (Expr.sum_int
                 (Expr.case
                    [ compound_condition, Event.value event ]
                    ~else_:(Expr.constant Db_type.int 0)))
              ~default:(Expr.constant Db_type.int64 0L)))
      in
      let has_related_event =
        Query.(
          from Event.table
          |> where (fun event -> Event.person_id event =. Person.id person)
          |> exists_expr)
      in
      Projection.both
        (Person.projection person)
        (Projection.both
           (Projection.expr has_related_event)
           (Projection.both
              (Query.multiset related_events)
              (Projection.both
                 (Query.multiset aggregate_events)
                 (Projection.expr (Expr.scalar_subquery aggregate_analysis)))))))
;;

let mega_query ~label_parameter ~limit_parameter ~offset_parameter =
  let input_rows_relation = input_rows_relation ~limit_parameter ~offset_parameter in
  let input_rows = Cte.select input_rows_relation in
  Cte.with_result cleanup_effect ~f:(fun () ->
    Cte.with_result maintenance_effect ~f:(fun () ->
      Cte.with_result recursive_sequence ~f:(fun sequence ->
        Cte.with_result input_rows ~f:(fun inputs ->
          Cte.with_result joined_events ~f:(fun joined_events ->
            Cte.with_result aggregate_metrics ~f:(fun metrics ->
              Cte.with_result outbox_rows ~f:(fun outbox ->
                Cte.with_result deleted_rows ~f:(fun deleted ->
                  let updated_rows =
                    Update.(
                      table Archive.table
                      |> from_cte deleted ~f:(fun archive removed update ->
                        update
                        |> set_expr
                             Archive.score_column
                             Expr.Int.Infix.(
                               Archive.score archive +. Deleted.score removed)
                        |> set_expr
                             Archive.label_column
                             (Expr.concat_value (Archive.label archive) " archived")
                        |> where (fun _ -> Archive.id archive =. Deleted.id removed))
                      |> returning Archive.projection)
                  in
                  let updated =
                    Postgresql.Cte.returning
                      ~table:Updated.table
                      ~columns:Updated.projection
                      updated_rows
                  in
                  Cte.with_result updated ~f:(fun updated ->
                    let audit_source =
                      Query.(
                        from_cte deleted
                        |> select (fun removed ->
                          Projection.both
                            (Projection.pair
                               (Deleted.id removed)
                               (Deleted.person_id removed))
                            (Projection.pair
                               (Deleted.label removed)
                               (Deleted.score removed))))
                    in
                    let audit_insert =
                      Insert.(
                        into Audit.table
                        |> from_select
                             (Columns.column Audit.id_column
                              |> Columns.add Audit.person_id_column
                              |> Columns.add Audit.label_column
                              |> Columns.add Audit.score_column)
                             audit_source
                        |> on_conflict
                             (Conflict_target.column Audit.person_id_column
                              |> Conflict_target.add Audit.score_column)
                        |> do_update (fun ~existing ~excluded ->
                          Conflict_update.(
                            empty
                            |> set_opt Audit.label_column (Some "expired")
                            |> set_expr_opt
                                 Audit.score_column
                                 (Some (Audit.score excluded))
                            |> where (Audit.score existing =. Audit.score excluded)))
                        |> returning Audit.projection)
                    in
                    let audit =
                      Postgresql.Cte.returning
                        ~table:Audit.table
                        ~columns:Audit.projection
                        audit_insert
                    in
                    Cte.with_result audit ~f:(fun audit ->
                      let combined_query =
                        let removed =
                          Query.(
                            from_cte deleted
                            |> select (fun removed ->
                              Projection.pair
                                (Deleted.person_id removed)
                                (Deleted.score removed)))
                        in
                        let changed =
                          Query.(
                            from_cte updated
                            |> select (fun changed ->
                              Projection.pair
                                (Updated.person_id changed)
                                (Updated.score changed)))
                        in
                        let order_by_person =
                          [ Column.name Deleted.person_id_column, `Asc
                          ; Column.name Deleted.score_column, `Desc
                          ]
                        in
                        let all_rows =
                          Query.union_all ~order_by:order_by_person removed changed
                        in
                        let distinct_rows =
                          Query.union ~order_by:order_by_person removed changed
                        in
                        let common_rows = Query.intersect distinct_rows changed in
                        let common_rows_with_duplicates =
                          Postgresql.Query.intersect_all
                            ~order_by:order_by_person
                            all_rows
                            common_rows
                        in
                        let except_rows =
                          Query.except
                            ~order_by:order_by_person
                            common_rows_with_duplicates
                            removed
                        in
                        let empty_except_all =
                          Postgresql.Query.except_all
                            ~order_by:order_by_person
                            changed
                            changed
                        in
                        Query.union ~order_by:order_by_person except_rows empty_except_all
                      in
                      let combined_definition =
                        Cte.select
                          ~materialization:`Not_materialized
                          (Derived_table.create
                             ~table:Combined.table
                             ~columns:Combined.projection
                             combined_query)
                      in
                      Cte.with_result combined_definition ~f:(fun combined ->
                        let summary_query =
                          Query.(
                            from_cte combined
                            |> left_join_cte audit ~on:(fun row audit ->
                              Combined.person_id row =. Audit.person_id audit)
                            |> where (fun (row, audit) ->
                              Expr.is_not_null (Audit.nullable_id audit)
                              &&. (Combined.score row >$ 0))
                            |> group_by (fun (row, _) -> Combined.person_id row)
                            |> having (fun _ -> Expr.count_all >$ 0L)
                            |> having (fun _ -> Expr.count_all <$ 100L)
                            |> order_by (fun (row, _) -> Combined.person_id row) `Desc
                            |> limit 10
                            |> offset 0
                            |> select (fun (row, _) ->
                              Projection.map3
                                ~f:(fun person_id event_count total_score ->
                                  person_id, event_count, total_score)
                                (Projection.expr (Combined.person_id row))
                                (Projection.expr Expr.count_all)
                                (Projection.expr (Expr.sum_int (Combined.score row)))))
                        in
                        let summary_definition =
                          Cte.select
                            ~materialization:`Materialized
                            (Derived_table.create
                               ~table:Summary.table
                               ~columns:Summary.projection
                               summary_query)
                        in
                        Cte.with_result summary_definition ~f:(fun summary ->
                          final_update
                            ~sequence
                            ~inputs
                            ~input_rows_relation
                            ~label_parameter
                            ~joined_events
                            ~metrics
                            ~outbox
                            ~summary))))))))))))
;;

let statement =
  Statement.For_dialect.query_many_exn ~dialect:Dialect.postgresql (fun parameters ->
    let label_parameter =
      parameters.column ~name:"mega_label" Person.name_column ~get:(fun _ -> "mega")
    in
    let limit_parameter = parameters.non_negative_int ~name:"input_rows_limit" ~get:fst in
    let offset_parameter =
      parameters.non_negative_int ~name:"input_rows_offset" ~get:snd
    in
    mega_query ~label_parameter ~limit_parameter ~offset_parameter)
;;

let%expect_test "one mega query compiles nested DML and relational paths" =
  statement
  |> Statement.sql_exn ~dialect:(Dialect.kind Dialect.postgresql) ~input:(20, 1)
  |> Stdlib.print_endline;
  [%expect
    {|
    WITH RECURSIVE
      "c0" AS (
        DELETE FROM "mega_cleanup"
      ),
      "c1" AS (
        UPDATE "mega_maintenance"
        SET
          "enabled" = $1
      ),
      "c2" (
        "value"
      ) AS (
        SELECT *
        FROM (
          SELECT
            $2
        ) AS s0
        UNION
        SELECT *
        FROM (
          SELECT
            COUNT(*)
        ) AS s0
        UNION ALL
        SELECT
          (t0."value" + $3)
        FROM "c2" AS t0
        WHERE
          (t0."value" < $4)
      ),
      "c3" (
        "id",
        "label"
      ) AS (
        SELECT *
        FROM (
          SELECT DISTINCT
            t0."field_1",
            LOWER(t1."label")
          FROM (
            SELECT
              t3."id" AS "field_1",
              t3."score" AS "field_2"
            FROM "public"."mega_people" AS t3
          ) AS t0
          INNER JOIN (SELECT
            "v"."column1" AS "id",
            "v"."column2" AS "label"
          FROM (VALUES
            (
              $5,
              $6
            ),
            (
              $7,
              $8
            )
          ) AS "v") AS t1
            ON (t0."field_1" = t1."id")
          LEFT JOIN (SELECT
            "v"."column1" AS "id",
            "v"."column2" AS "label"
          FROM (VALUES
            (
              $9,
              $10
            ),
            (
              $11,
              $12
            )
          ) AS "v") AS t2
            ON (t0."field_1" = t2."id")
          WHERE
            (
              (t0."field_1" > $13)
              AND (
                (CAST($14 AS bigint) IS NULL)
                OR (CAST($15 AS bigint) IS NOT NULL)
              )
            )
          ORDER BY
            t0."field_1" ASC
          LIMIT $16
          OFFSET $17
        ) AS s0
        UNION ALL
        SELECT *
        FROM (
          SELECT
            t0."id",
            t0."label"
          FROM (SELECT
            "v"."column1" AS "id",
            "v"."column2" AS "label"
          FROM (VALUES
            (
              $18,
              $19
            ),
            (
              $20,
              $21
            )
          ) AS "v") AS t0
        ) AS s0
        ORDER BY
          "field_1" ASC
      ),
      "c4" (
        "id",
        "person_id",
        "label"
      ) AS (
        SELECT
          t0."id",
          t0."person_id",
          t0."label"
        FROM (
          SELECT
            t5."id" AS "id",
            t5."person_id" AS "person_id",
            t5."label" AS "label"
          FROM "mega_events" AS t5
        ) AS t0
        INNER JOIN (
          SELECT
            t5."id" AS "id",
            t5."person_id" AS "person_id",
            t5."label" AS "label"
          FROM "mega_events" AS t5
        ) AS t1
          ON (t0."id" = t1."id")
        LEFT JOIN (
          SELECT
            t5."id" AS "id",
            t5."person_id" AS "person_id",
            t5."label" AS "label"
          FROM "mega_events" AS t5
        ) AS t2
          ON (t0."id" = t2."id")
        INNER JOIN "mega_events" AS t3
          ON (t0."id" = t3."id")
        LEFT JOIN "mega_events" AS t4
          ON (t0."id" = t4."id")
      ),
      "c5" (
        "count_all",
        "count_id",
        "count_distinct",
        "sum_int",
        "sum_nullable_int",
        "sum_float",
        "sum_nullable_float",
        "min_text",
        "max_text",
        "min_nullable_text",
        "max_nullable_text",
        "sum_int64",
        "sum_nullable_int64",
        "sum_numeric",
        "sum_nullable_numeric",
        "min_numeric",
        "max_numeric",
        "min_nullable_numeric",
        "max_nullable_numeric"
      ) AS (
        SELECT
          COUNT(*),
          COUNT(t0."id"),
          COUNT(DISTINCT t0."person_id"),
          SUM(t0."value"),
          SUM(t0."nullable_value"),
          SUM(t0."float_value"),
          SUM(t0."nullable_float_value"),
          MIN(t0."label"),
          MAX(t0."label"),
          MIN(t0."nullable_label"),
          MAX(t0."nullable_label"),
          SUM(t0."id"),
          SUM(t0."nullable_id"),
          SUM(t0."numeric_value"),
          SUM(t0."nullable_numeric_value"),
          MIN(t0."numeric_value"),
          MAX(t0."numeric_value"),
          MIN(t0."nullable_numeric_value"),
          MAX(t0."nullable_numeric_value")
        FROM "mega_events" AS t0
        WHERE
          (t0."id" > $22)
      ),
      "c6" (
        "id",
        "label"
      ) AS (
        INSERT INTO "mega_outbox" (
          "id",
          "label"
        )
        VALUES
          ($23, $24),
          ($25, $26)
        ON CONFLICT DO NOTHING
        RETURNING
          "id",
          "label"
      ),
      "c7" (
        "id",
        "person_id",
        "label",
        "score"
      ) AS (
        DELETE FROM "mega_expired"
        WHERE
          ("score" < $27)
        RETURNING
          "id",
          "person_id",
          "label",
          "score"
      ),
      "c8" (
        "id",
        "person_id",
        "label",
        "score"
      ) AS (
        UPDATE "mega_archive" AS t0
        SET
          "score" = (t0."score" + t1."score"),
          "label" = (t0."label" || $28)
        FROM "c7" AS t1
        WHERE
          (t0."id" = t1."id")
        RETURNING
          t0."id",
          t0."person_id",
          t0."label",
          t0."score"
      ),
      "c9" (
        "id",
        "person_id",
        "label",
        "score"
      ) AS (
        INSERT INTO "mega_audit" AS t0 (
          "id",
          "person_id",
          "label",
          "score"
        )
        SELECT
          t0."id",
          t0."person_id",
          t0."label",
          t0."score"
        FROM "c7" AS t0
        ON CONFLICT (
          "person_id",
          "score"
        )
        DO UPDATE
        SET
          "label" = $29,
          "score" = excluded."score"
        WHERE
          (t0."score" = excluded."score")
        RETURNING
          "id",
          "person_id",
          "label",
          "score"
      ),
      "c10" (
        "person_id",
        "score"
      ) AS NOT MATERIALIZED (
        SELECT *
        FROM (
          SELECT *
          FROM (
            SELECT *
            FROM (
              SELECT *
              FROM (
                SELECT
                  t0."person_id",
                  t0."score"
                FROM "c7" AS t0
              ) AS s0
              UNION ALL
              SELECT *
              FROM (
                SELECT
                  t0."person_id",
                  t0."score"
                FROM "c8" AS t0
              ) AS s0
              ORDER BY
                "person_id" ASC,
                "score" DESC
            ) AS s0
            INTERSECT ALL
            SELECT *
            FROM (
              SELECT *
              FROM (
                SELECT *
                FROM (
                  SELECT
                    t0."person_id",
                    t0."score"
                  FROM "c7" AS t0
                ) AS s0
                UNION
                SELECT *
                FROM (
                  SELECT
                    t0."person_id",
                    t0."score"
                  FROM "c8" AS t0
                ) AS s0
                ORDER BY
                  "person_id" ASC,
                  "score" DESC
              ) AS s0
              INTERSECT
              SELECT *
              FROM (
                SELECT
                  t0."person_id",
                  t0."score"
                FROM "c8" AS t0
              ) AS s0
            ) AS s0
            ORDER BY
              "person_id" ASC,
              "score" DESC
          ) AS s0
          EXCEPT
          SELECT *
          FROM (
            SELECT
              t0."person_id",
              t0."score"
            FROM "c7" AS t0
          ) AS s0
          ORDER BY
            "person_id" ASC,
            "score" DESC
        ) AS s0
        UNION
        SELECT *
        FROM (
          SELECT *
          FROM (
            SELECT
              t0."person_id",
              t0."score"
            FROM "c8" AS t0
          ) AS s0
          EXCEPT ALL
          SELECT *
          FROM (
            SELECT
              t0."person_id",
              t0."score"
            FROM "c8" AS t0
          ) AS s0
          ORDER BY
            "person_id" ASC,
            "score" DESC
        ) AS s0
        ORDER BY
          "person_id" ASC,
          "score" DESC
      ),
      "c11" (
        "person_id",
        "event_count",
        "total_score"
      ) AS MATERIALIZED (
        SELECT
          t0."person_id",
          COUNT(*),
          SUM(t0."score")
        FROM "c10" AS t0
        LEFT JOIN "c9" AS t1
          ON (t0."person_id" = t1."person_id")
        WHERE
          (
            (t1."id" IS NOT NULL)
            AND (t0."score" > $30)
          )
        GROUP BY
          t0."person_id"
        HAVING
          (
            (COUNT(*) > $31)
            AND (COUNT(*) < $32)
          )
        ORDER BY
          t0."person_id" DESC
        LIMIT 10
        OFFSET 0
      )
    UPDATE "public"."mega_people" AS t0
    SET
      "active" = $33,
      "nickname" = $34,
      "bio" = $35,
      "status" = DEFAULT,
      "score" = (t0."score" + COALESCE(t4."total_score", $36)),
      "name" = ((CASE
        WHEN (t4."event_count" > $37) THEN UPPER(t0."name")
        ELSE LOWER(t0."name")
      END) || $38)
    FROM "mega_events" AS t1,
      (
        SELECT *
        FROM (
          SELECT DISTINCT
            t5."field_1" AS "id",
            LOWER(t6."label") AS "label"
          FROM (
            SELECT
              t8."id" AS "field_1",
              t8."score" AS "field_2"
            FROM "public"."mega_people" AS t8
          ) AS t5
          INNER JOIN (SELECT
            "v"."column1" AS "id",
            "v"."column2" AS "label"
          FROM (VALUES
            (
              $39,
              $40
            ),
            (
              $41,
              $42
            )
          ) AS "v") AS t6
            ON (t5."field_1" = t6."id")
          LEFT JOIN (SELECT
            "v"."column1" AS "id",
            "v"."column2" AS "label"
          FROM (VALUES
            (
              $43,
              $44
            ),
            (
              $45,
              $46
            )
          ) AS "v") AS t7
            ON (t5."field_1" = t7."id")
          WHERE
            (
              (t5."field_1" > $47)
              AND (
                (CAST($48 AS bigint) IS NULL)
                OR (CAST($49 AS bigint) IS NOT NULL)
              )
            )
          ORDER BY
            t5."field_1" ASC
          LIMIT $16
          OFFSET $17
        ) AS s0
        UNION ALL
        SELECT *
        FROM (
          SELECT
            t5."id" AS "id",
            t5."label" AS "label"
          FROM (SELECT
            "v"."column1" AS "id",
            "v"."column2" AS "label"
          FROM (VALUES
            (
              $50,
              $51
            ),
            (
              $52,
              $53
            )
          ) AS "v") AS t5
        ) AS s0
        ORDER BY
          "id" ASC
      ) AS t2,
      (
        SELECT
          t5."id" AS "field_1",
          t5."score" AS "field_2"
        FROM "public"."mega_people" AS t5
      ) AS t3,
      "c11" AS t4
    WHERE
      (
        (t0."id" = t4."person_id")
        AND (CAST($54 AS boolean) IS NOT NULL)
        AND (CAST($55 AS integer) IS NOT NULL)
        AND (CAST($56 AS bigint) IS NOT NULL)
        AND (CAST($57 AS double precision) IS NOT NULL)
        AND (CAST($58 AS numeric) IS NOT NULL)
        AND (CAST($59 AS text) IS NOT NULL)
        AND (CAST($60 AS bytea) IS NOT NULL)
        AND (CAST($61 AS date) IS NOT NULL)
        AND (CAST($62 AS timestamp with time zone) IS NOT NULL)
        AND (CAST($63 AS uuid) IS NOT NULL)
        AND (CAST($64 AS text) IS NOT NULL)
        AND (t1."person_id" = t0."id")
        AND (t2."id" = t0."id")
        AND (t3."field_1" = t0."id")
        AND (t0."name" IS DISTINCT FROM $59)
        AND ((EXISTS (
          SELECT
            1
          FROM "c2" AS t5
          WHERE
            (t5."value" = t0."id")
        )) = $65)
        AND ((EXISTS (
          SELECT
            1
          FROM "mega_events" AS t5
          WHERE
            (t5."person_id" = t0."id")
        )) = $66)
        AND ((EXISTS (
          SELECT
            1
          FROM "c3" AS t5
          WHERE
            (t5."id" = t0."id")
        )) = $67)
        AND ((EXISTS (
          SELECT
            1
          FROM (
            SELECT
              t8."id" AS "field_1",
              t8."score" AS "field_2"
            FROM "public"."mega_people" AS t8
          ) AS t5
          INNER JOIN (
            SELECT
              t8."id" AS "field_1",
              t8."score" AS "field_2"
            FROM "public"."mega_people" AS t8
          ) AS t6
            ON (t5."field_1" = t6."field_1")
          LEFT JOIN (
            SELECT
              t8."id" AS "field_1",
              t8."score" AS "field_2"
            FROM "public"."mega_people" AS t8
          ) AS t7
            ON (t5."field_1" = t7."field_1")
        )) = $68)
        AND ((EXISTS (
          SELECT
            1
          FROM "c4" AS t5
          INNER JOIN "c4" AS t6
            ON (t5."id" = t6."id")
          WHERE
            (t5."person_id" = t0."id")
        )) = $69)
        AND ((EXISTS (
          SELECT
            1
          FROM "c5" AS t5
          WHERE
            (t5."count_all" > $70)
        )) = $71)
        AND ((EXISTS (
          SELECT
            1
          FROM "c6" AS t5
          WHERE
            (t5."id" > $72)
        )) = $73)
        AND (COALESCE((
          SELECT
            COUNT(*)
          FROM "mega_events" AS t5
          WHERE
            (t5."person_id" = t0."id")
        ), $74) > $75)
        AND (t0."id" IN (
          $76,
          $77
        ))
        AND (t0."id" NOT IN ($78))
        AND (t0."name" IN (
          $79,
          $80
        ))
        AND (t0."name" NOT IN ($81))
        AND (t0."score" BETWEEN $82 AND $83)
        AND (NOT (t0."nickname" IS NULL))
        AND (NOT EXISTS (
          SELECT
            1
          FROM "mega_events" AS t5
          WHERE
            (t5."person_id" > t0."id")
        ))
        AND (t0."id" IN (
          SELECT
            t5."person_id"
          FROM "mega_events" AS t5
          WHERE
            (t5."person_id" = t0."id")
          LIMIT 1
        ))
      )
    RETURNING
      t0."id",
      t0."name",
      (EXISTS (
        SELECT
          1
        FROM "mega_events" AS t5
        WHERE
          (t5."person_id" = t0."id")
      )),
      CAST(
        (
          SELECT
            COALESCE(
              JSONB_AGG(
                JSONB_BUILD_ARRAY(
                  m0."v0",
                  m0."v1",
                  m0."v2"
                )
              ),
              JSONB_BUILD_ARRAY()
            )
          FROM LATERAL (
            SELECT
              t5."id" AS "v0",
              t5."person_id" AS "v1",
              t5."label" AS "v2"
            FROM "mega_events" AS t5
            WHERE
              (t5."person_id" = t0."id")
            ORDER BY
              t5."id" ASC
            LIMIT 5
          ) AS m0
        )
        AS TEXT
      ),
      CAST(
        (
          SELECT
            COALESCE(
              JSONB_AGG(
                JSONB_BUILD_ARRAY(
                  m0."v0"
                )
              ),
              JSONB_BUILD_ARRAY()
            )
          FROM LATERAL (
            SELECT
              COALESCE(
                JSONB_AGG(
                  JSONB_BUILD_ARRAY(
                    t5."id",
                    t5."person_id",
                    t5."label",
                    (
                      SELECT
                        COALESCE(
                          JSONB_AGG(
                            JSONB_BUILD_ARRAY(
                              m0."v0"
                            )
                          ),
                          JSONB_BUILD_ARRAY()
                        )
                      FROM LATERAL (
                        SELECT
                          t6."id" AS "v0"
                        FROM "mega_events" AS t6
                        WHERE
                          (t6."person_id" = t0."id")
                      ) AS m0
                    ),
                    t5."happened_on",
                    t5."external_id",
                    t5."mapped_label"
                  )
                  ORDER BY t5."id" ASC
                ) FILTER (
                  WHERE (
                    (t5."person_id" = t0."id")
                    AND ((EXISTS (
                      SELECT
                        1
                      FROM "mega_events" AS t6
                      WHERE
                        (
                          (t6."person_id" = t0."id")
                          AND (t6."value" > $84)
                        )
                    )) = $85)
                  )
                ),
                JSONB_BUILD_ARRAY()
              ) AS "v0"
            FROM "mega_events" AS t5
          ) AS m0
        )
        AS TEXT
      ),
      (
        SELECT
          COALESCE(SUM((CASE
            WHEN (
              (t5."id" = (t5."id" + $86))
              AND ((t5."id" - $87) = $88)
              AND ((t5."id" * $89) = t5."id")
              AND ((t5."id" / $90) = t5."id")
              AND (t5."id" <> $91)
              AND (t5."id" <> $92)
              AND (t5."id" < $93)
              AND (t5."id" <= $94)
              AND (t5."id" >= $95)
              AND (t5."id" <= $96)
              AND (t5."id" >= $97)
              AND (t5."nullable_id" IS NULL)
              AND (t5."nullable_id" IS NOT NULL)
              AND (t5."id" IN (
                $98,
                $99
              ))
              AND (t5."id" NOT IN ($100))
              AND (t5."id" IN ($101))
              AND (t5."id" NOT IN ($102))
              AND (t5."id" BETWEEN $103 AND $104)
              AND (t5."id" IN (
                SELECT
                  t6."id"
                FROM "mega_events" AS t6
                WHERE
                  (t6."id" = t5."id")
                LIMIT 1
              ))
              AND (t5."id" NOT IN (
                SELECT
                  t6."id"
                FROM "mega_events" AS t6
                WHERE
                  (t6."id" = t5."id")
                LIMIT 1
              ))
              AND (EXISTS (
                SELECT
                  1
                FROM "mega_events" AS t6
                WHERE
                  (t6."person_id" = t5."person_id")
              ))
              AND (NOT EXISTS (
                SELECT
                  1
                FROM "mega_events" AS t6
                WHERE
                  (t6."person_id" = t5."person_id")
              ))
              AND (t5."label" IS DISTINCT FROM $105)
              AND (t5."label" LIKE $106)
              AND (CHAR_LENGTH(t5."label") > $107)
              AND ((
                SELECT
                  t6."nullable_id"
                FROM "mega_events" AS t6
                WHERE
                  (t6."id" = t5."id")
                LIMIT 1
              ) = t5."id")
              AND (NOT (t5."id" > $108))
              AND ((LOWER(t5."label") || $109) LIKE $110)
              AND (COALESCE(t5."nullable_id", $111) > $112)
              AND ((CASE
                WHEN TRUE THEN t5."id"
                ELSE $113
              END) > $114)
              AND (CURRENT_TIMESTAMP = CURRENT_TIMESTAMP)
            ) THEN t5."value"
            ELSE $115
          END)), $116)
        FROM "mega_events" AS t5
      )
    |}];
  (match
     Statement.sql_exn ~dialect:(Dialect.kind Dialect.postgresql) ~input:(-1, 1) statement
   with
   | exception Failure message -> Stdlib.print_endline message
   | _ -> failwith "negative pagination value unexpectedly rendered SQL");
  [%expect {|input_rows_limit must be non-negative, got -1|}]
;;
