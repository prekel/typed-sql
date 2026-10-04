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

module Portable_person_ids = struct
  type row

  let table : row Table.t = Table.v_exn "mega_portable_person_ids"
  let id_column = Column.v_exn table "id" Db_type.int64
  let id reference = Expr.column reference id_column
  let projection reference = Projection.expr (id reference)
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

let input_rows_query ~limit_parameter ~offset_parameter ~optional_person_id_parameter =
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
           optional_person_id_parameter
           ~f:(fun (((person_id, _), _), _) optional_person_id ->
             person_id =. optional_person_id)
      |> distinct
      |> order_by (fun (((person_id, _), _), _) -> person_id) `Asc
      |> Postgresql.Query.offset_param_opt offset_parameter
      |> Postgresql.Query.limit_param_opt limit_parameter
      |> select (fun (((person_id, _), tag), _) ->
        Projection.pair person_id (Expr.lower (Tag.label tag))))
  in
  let values_branch = Query.(from_values static_tags |> select Tag.projection) in
  Query.union_all
    ~order_by:[ Identifier.of_string_exn "field_1", `Asc ]
    inferred_branch
    values_branch
;;

let input_rows_relation
      ~optional_limit_parameter
      ~offset_parameter
      ~optional_person_id_parameter
  : (Input_rows.row, Dialect.postgresql) Derived_table.t
  =
  Derived_table.create
    ~table:Input_rows.table
    ~columns:Input_rows.projection
    (input_rows_query
       ~limit_parameter:optional_limit_parameter
       ~offset_parameter
       ~optional_person_id_parameter)
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

let mega_local_timestamp =
  let parsed =
    Local_timestamp.of_string "2026-09-30 12:34:56.000789" |> Result.ok_or_failwith
  in
  let created =
    Local_timestamp.create
      ~date:(Local_timestamp.date parsed)
      ~hour:(Local_timestamp.hour parsed)
      ~minute:(Local_timestamp.minute parsed)
      ~second:(Local_timestamp.second parsed)
      ~microsecond:(Local_timestamp.microsecond parsed)
    |> Result.ok_or_failwith
  in
  let encoded =
    Db_type.Postgresql.encode_text Db_type.Postgresql.local_timestamp created
    |> Result.ok_or_failwith
  in
  Db_type.Postgresql.decode_text Db_type.Postgresql.local_timestamp encoded
  |> Result.ok_or_failwith
;;

let mega_interval =
  let parsed =
    Interval.of_string "1 year 2 mons 3 days 04:05:06.000007" |> Result.ok_or_failwith
  in
  let created =
    Interval.create
      ~months:(Interval.months parsed)
      ~days:(Interval.days parsed)
      ~microseconds:(Interval.microseconds parsed)
  in
  let encoded =
    Db_type.Postgresql.encode_text Db_type.Postgresql.interval created
    |> Result.ok_or_failwith
  in
  Db_type.Postgresql.decode_text Db_type.Postgresql.interval encoded
  |> Result.ok_or_failwith
;;

let mega_pg_array =
  let created =
    Pg_array.create ~dimensions:[ 2 ] ~lower_bounds:[ 0 ] ~elements:[ Some 1L; None ]
    |> Result.ok_or_failwith
  in
  let preserved =
    Pg_array.create
      ~dimensions:(Pg_array.dimensions created)
      ~lower_bounds:(Pg_array.lower_bounds created)
      ~elements:(Pg_array.elements created)
    |> Result.ok_or_failwith
  in
  let array_type = Db_type.Postgresql.array Db_type.int64 in
  let encoded =
    Db_type.Postgresql.encode_text array_type preserved |> Result.ok_or_failwith
  in
  Db_type.Postgresql.decode_text array_type encoded |> Result.ok_or_failwith
;;

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

let recursive_sequence =
  Cte.recursive_relation
    ~union:`Union_all
    ~anchor:(Query.select_one_relation (Expr.constant Db_type.int64 1L))
    ~step:(fun sequence ->
      Query.(
        from_cte_relation sequence
        |> where (fun number -> number <$ 4L)
        |> select_relation (fun number ->
          Derived_table.Fields.expr
            Expr.Int64.Infix.(number +. Expr.constant Db_type.int64 1L))))
;;

let computed_event_fields id person_id label depth =
  Derived_table.Fields.both
    (Derived_table.Fields.both
       (Derived_table.Fields.expr id)
       (Derived_table.Fields.expr person_id))
    (Derived_table.Fields.both
       (Derived_table.Fields.expr label)
       (Derived_table.Fields.expr depth))
;;

let recursive_events =
  let anchor =
    Query.(
      from Event.table
      |> select_relation (fun event ->
        computed_event_fields
          (Event.id event)
          (Event.person_id event)
          (Event.label event)
          (Expr.constant Db_type.int 0)))
  in
  Cte.recursive_relation ~union:`Union_all ~anchor ~step:(fun events ->
    Query.(
      from Event.table
      |> inner_join_cte_relation events ~on:(fun event ((id, _), _) ->
        Event.id event >. id)
      |> select_relation (fun (event, ((_, _), (_, depth))) ->
        computed_event_fields
          (Event.id event)
          (Event.person_id event)
          (Event.label event)
          Expr.Int.Infix.(depth +. Expr.constant Db_type.int 1))))
;;

let cleanup_command = Delete.(from Cleanup.table |> all_rows |> command)
let cleanup_effect = Postgresql.Cte.command cleanup_command

let maintenance_effect =
  Postgresql.Cte.command
    Update.(
      table Maintenance.table
      |> set Maintenance.enabled_column true
      |> all_rows
      |> command)
;;

let person_result_projection person =
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
             (Projection.expr (Expr.scalar_subquery aggregate_analysis)))))
;;

let final_update
      ~sequence
      ~recursive_events
      ~inputs
      ~input_rows_relation
      ~label_parameter
      ~ids_parameter
      ~joined_events
      ~metrics
      ~outbox
      ~summary
  =
  Update.(
    table Person.table
    |> from Event.table ~f:(fun _person event update ->
      update
      |> from_derived input_rows_relation ~f:(fun _person input update ->
        update
        |> from_relation inferred_people ~f:(fun _person (inferred_person_id, _) update ->
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
                from_cte_relation sequence
                |> where (fun number -> number =. Person.id person)
                |> exists_expr)
            in
            let has_computed_recursive_event =
              Query.(
                from_cte_relation recursive_events
                |> where (fun ((_, person_id), _) -> person_id =. Person.id person)
                |> exists_expr)
            in
            let has_related_event =
              Query.(
                from Event.table
                |> where (fun event -> Event.person_id event =. Person.id person)
                |> order_by Event.id `Asc
                |> limit_one
                |> Postgresql.Query.for_update
                     ~of_:(fun event -> [ Postgresql.Query.target event ])
                     ~skip_locked:true
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
            let event_labels =
              Query.(
                from Event.table
                |> where (fun event -> Event.person_id event =. Person.id person)
                |> select_scalar (fun event ->
                  Postgresql.string_agg_nullable
                    ~order_by:[ Aggregate_order.asc (Event.id event) ]
                    ~delimiter:(Expr.constant Db_type.text ",")
                    (Event.nullable_label event)))
              |> Expr.scalar_subquery_nullable
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
              &&. (has_computed_recursive_event =$ true)
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
              &&. Query.in_subquery (Person.id person) first_event_person_id
              &&. (event_labels
                   =. Expr.constant (Db_type.option Db_type.text) (Some "optional"))
              &&. Postgresql.Expr.equals_any_list (Person.id person) ids_parameter
              &&. is_not_null_parameter
                    Db_type.Postgresql.local_timestamp
                    mega_local_timestamp
              &&. is_not_null_parameter Db_type.Postgresql.interval mega_interval
              &&. Postgresql.Expr.equals_any
                    (Expr.constant Db_type.int64 1L)
                    (Expr.constant (Db_type.Postgresql.array Db_type.int64) mega_pg_array))))))
    |> returning person_result_projection)
;;

let mega_query
      ~label_parameter
      ~ids_parameter
      ~limit_parameter
      ~offset_parameter
      ~optional_person_id_parameter
      ~optional_limit_parameter
  =
  let input_rows_relation =
    input_rows_relation
      ~optional_limit_parameter
      ~offset_parameter
      ~optional_person_id_parameter
  in
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
                        Cte.with_result recursive_events ~f:(fun recursive_events ->
                          let summary_query =
                            Query.(
                              from_cte combined
                              |> left_join_cte audit ~on:(fun row audit ->
                                Combined.person_id row =. Audit.person_id audit)
                              |> left_join_cte_relation
                                   recursive_events
                                   ~on:(fun (row, _) ((_, person_id), _) ->
                                     Combined.person_id row =. person_id)
                              |> where (fun ((row, audit), ((_, person_id), _)) ->
                                Expr.is_not_null (Audit.nullable_id audit)
                                &&. Expr.is_not_null person_id
                                &&. (Combined.score row >$ 0))
                              |> group_by (fun ((row, _), _) -> Combined.person_id row)
                              |> having (fun _ -> Expr.count_all >$ 0L)
                              |> having (fun _ -> Expr.count_all <$ 100L)
                              |> order_by
                                   (fun ((row, _), _) -> Combined.person_id row)
                                   `Desc
                              |> offset 0
                              |> Postgresql.Query.fetch_with_ties_param limit_parameter
                              |> select (fun ((row, _), _) ->
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
                              ~recursive_events
                              ~inputs
                              ~input_rows_relation
                              ~label_parameter
                              ~ids_parameter
                              ~joined_events
                              ~metrics
                              ~outbox
                              ~summary)))))))))))))
;;

let postgresql_statement =
  Statement.with_parameters ~dialect:Dialect.postgresql (fun ~params ->
    let%map.Statement.Parameters label_parameter =
      params.column ~name:"mega_label" Person.name_column ~get:(fun _ -> "mega")
    and ids_parameter =
      params.expr (Db_type.Postgresql.array_list Db_type.int64) ~get:(fun (ids, _, _) ->
        ids)
    and limit_parameter =
      params.non_negative_int ~name:"input_rows_limit" ~get:(fun (_, limit, _) -> limit)
    and offset_parameter =
      params.non_negative_int_opt ~name:"input_rows_offset" ~get:(fun (_, _, offset) ->
        Some offset)
    and optional_person_id_parameter =
      params.optional_expr ~name:"optional_mega_person_id" Db_type.int64 ~get:(fun _ ->
        None)
    and optional_limit_parameter =
      params.non_negative_int_opt
        ~name:"optional_input_rows_limit"
        ~get:(fun (_, limit, _) -> Some limit)
    in
    params.query_many
      (mega_query
         ~label_parameter
         ~ids_parameter
         ~limit_parameter
         ~offset_parameter
         ~optional_person_id_parameter
         ~optional_limit_parameter))
;;

let sqlite_statement =
  Statement.with_parameters ~dialect:Dialect.sqlite (fun ~params ->
    let%map.Statement.Parameters label_parameter =
      params.column ~name:"mega_label" Person.name_column ~get:(fun _ -> "mega")
    and limit_parameter =
      params.non_negative_int ~name:"input_rows_limit" ~get:(fun (_, limit, _) -> limit)
    and offset_parameter =
      params.non_negative_int ~name:"input_rows_offset" ~get:(fun (_, _, offset) ->
        offset)
    in
    let id_query =
      Query.union
        Query.(
          from Person.table
          |> where (fun person -> Person.name person =. label_parameter)
          |> select (fun person -> Projection.expr (Person.id person)))
        Query.(
          from Person.table
          |> where (fun person -> Person.id person >$ 0L)
          |> select (fun person -> Projection.expr (Person.id person)))
    in
    let id_relation =
      Derived_table.create
        ~table:Portable_person_ids.table
        ~columns:Portable_person_ids.projection
        id_query
    in
    params.query_many
      Query.(
        from Person.table
        |> where (fun person ->
          Person.name person
          =. label_parameter
          &&. Query.exists
                Query.(
                  from_derived id_relation
                  |> where (fun id -> Portable_person_ids.id id =. Person.id person)))
        |> group_by Person.id
        |> group_by Person.name
        |> having (fun _ -> Expr.count_all >$ 0L)
        |> offset_param offset_parameter
        |> limit_param limit_parameter
        |> select person_result_projection))
;;

let statement =
  Statement.choose_dialect ~postgresql:postgresql_statement ~sqlite:sqlite_statement
;;

let%expect_test "PostgreSQL mega query compiles nested DML and relational paths" =
  let sql, inspection =
    Statement.inspect_exn ~dialect:Postgresql ~input:([ 1L ], 20, 1) statement
  in
  Stdlib.print_endline sql;
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
        "field_1"
      ) AS (
        SELECT
          $2
        UNION ALL
        SELECT
          (t0."field_1" + $3)
        FROM "c2" AS t0
        WHERE
          (t0."field_1" < $4)
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
                OR (t0."field_1" = $14)
              )
            )
          ORDER BY
            t0."field_1" ASC
          LIMIT $15
          OFFSET $16
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
              $17,
              $18
            ),
            (
              $19,
              $20
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
          (t0."id" > $21)
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
          ($22, $23),
          ($24, $25)
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
          ("score" < $26)
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
          "label" = (t0."label" || $27)
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
          "label" = $28,
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
        "field_1",
        "field_2",
        "field_3",
        "field_4"
      ) AS (
        SELECT
          t0."id",
          t0."person_id",
          t0."label",
          $29
        FROM "mega_events" AS t0
        UNION ALL
        SELECT
          t0."id",
          t0."person_id",
          t0."label",
          (t1."field_4" + $30)
        FROM "mega_events" AS t0
        INNER JOIN "c11" AS t1
          ON (t0."id" > t1."field_1")
      ),
      "c12" (
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
        LEFT JOIN "c11" AS t2
          ON (t0."person_id" = t2."field_2")
        WHERE
          (
            (t1."id" IS NOT NULL)
            AND (t2."field_2" IS NOT NULL)
            AND (t0."score" > $31)
          )
        GROUP BY
          t0."person_id"
        HAVING
          (
            (COUNT(*) > $32)
            AND (COUNT(*) < $33)
          )
        ORDER BY
          t0."person_id" DESC
        OFFSET 0
        FETCH FIRST $34 ROWS WITH TIES
      )
    UPDATE "public"."mega_people" AS t0
    SET
      "active" = $35,
      "nickname" = $36,
      "bio" = $37,
      "status" = DEFAULT,
      "score" = (t0."score" + COALESCE(t4."total_score", $38)),
      "name" = ((CASE
        WHEN (t4."event_count" > $39) THEN UPPER(t0."name")
        ELSE LOWER(t0."name")
      END) || $40)
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
              $41,
              $42
            ),
            (
              $43,
              $44
            )
          ) AS "v") AS t6
            ON (t5."field_1" = t6."id")
          LEFT JOIN (SELECT
            "v"."column1" AS "id",
            "v"."column2" AS "label"
          FROM (VALUES
            (
              $45,
              $46
            ),
            (
              $47,
              $48
            )
          ) AS "v") AS t7
            ON (t5."field_1" = t7."id")
          WHERE
            (
              (t5."field_1" > $49)
              AND (
                (CAST($14 AS bigint) IS NULL)
                OR (t5."field_1" = $14)
              )
            )
          ORDER BY
            t5."field_1" ASC
          LIMIT $15
          OFFSET $16
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
      "c12" AS t4
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
            (t5."field_1" = t0."id")
        )) = $65)
        AND ((EXISTS (
          SELECT
            1
          FROM "c11" AS t5
          WHERE
            (t5."field_2" = t0."id")
        )) = $66)
        AND ((EXISTS (
          SELECT
            1
          FROM "mega_events" AS t5
          WHERE
            (t5."person_id" = t0."id")
          ORDER BY
            t5."id" ASC
          LIMIT 1
          FOR UPDATE OF t5 SKIP LOCKED
        )) = $67)
        AND ((EXISTS (
          SELECT
            1
          FROM "c3" AS t5
          WHERE
            (t5."id" = t0."id")
        )) = $68)
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
        )) = $69)
        AND ((EXISTS (
          SELECT
            1
          FROM "c4" AS t5
          INNER JOIN "c4" AS t6
            ON (t5."id" = t6."id")
          WHERE
            (t5."person_id" = t0."id")
        )) = $70)
        AND ((EXISTS (
          SELECT
            1
          FROM "c5" AS t5
          WHERE
            (t5."count_all" > $71)
        )) = $72)
        AND ((EXISTS (
          SELECT
            1
          FROM "c6" AS t5
          WHERE
            (t5."id" > $73)
        )) = $74)
        AND (COALESCE((
          SELECT
            COUNT(*)
          FROM "mega_events" AS t5
          WHERE
            (t5."person_id" = t0."id")
        ), $75) > $76)
        AND (t0."id" IN (
          $77,
          $78
        ))
        AND (t0."id" NOT IN ($79))
        AND (t0."name" IN (
          $80,
          $81
        ))
        AND (t0."name" NOT IN ($82))
        AND (t0."score" BETWEEN $83 AND $84)
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
        AND ((
          SELECT
            STRING_AGG(
              t5."nullable_label",
              $85
              ORDER BY t5."id" ASC
            )
          FROM "mega_events" AS t5
          WHERE
            (t5."person_id" = t0."id")
        ) = $86)
        AND (t0."id" = ANY(CAST($87 AS bigint[])))
        AND (CAST(CAST($88 AS "pg_catalog"."timestamp") AS "pg_catalog"."timestamp") IS NOT NULL)
        AND (CAST(CAST($89 AS "pg_catalog"."interval") AS "pg_catalog"."interval") IS NOT NULL)
        AND ($90 = ANY(CAST($91 AS bigint[])))
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
                          AND (t6."value" > $92)
                        )
                    )) = $93)
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
              (t5."id" = (t5."id" + $94))
              AND ((t5."id" - $95) = $96)
              AND ((t5."id" * $97) = t5."id")
              AND ((t5."id" / $98) = t5."id")
              AND (t5."id" <> $99)
              AND (t5."id" <> $100)
              AND (t5."id" < $101)
              AND (t5."id" <= $102)
              AND (t5."id" >= $103)
              AND (t5."id" <= $104)
              AND (t5."id" >= $105)
              AND (t5."nullable_id" IS NULL)
              AND (t5."nullable_id" IS NOT NULL)
              AND (t5."id" IN (
                $106,
                $107
              ))
              AND (t5."id" NOT IN ($108))
              AND (t5."id" IN ($109))
              AND (t5."id" NOT IN ($110))
              AND (t5."id" BETWEEN $111 AND $112)
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
              AND (t5."label" IS DISTINCT FROM $113)
              AND (t5."label" LIKE $114)
              AND (CHAR_LENGTH(t5."label") > $115)
              AND ((
                SELECT
                  t6."nullable_id"
                FROM "mega_events" AS t6
                WHERE
                  (t6."id" = t5."id")
                LIMIT 1
              ) = t5."id")
              AND (NOT (t5."id" > $116))
              AND ((LOWER(t5."label") || $117) LIKE $118)
              AND (COALESCE(t5."nullable_id", $119) > $120)
              AND ((CASE
                WHEN TRUE THEN t5."id"
                ELSE $121
              END) > $122)
              AND (CURRENT_TIMESTAMP = CURRENT_TIMESTAMP)
            ) THEN t5."value"
            ELSE $123
          END)), $124)
        FROM "mega_events" AS t5
      )
    |}];
  Stdlib.print_endline @@ Sexp.to_string_hum @@ Statement.sexp_of_inspection inspection;
  [%expect
    {|
    ((dialect Postgresql)
     (parameters
      (((position 1) (placeholder $1) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 2) (placeholder $2) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 3) (placeholder $3) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 4) (placeholder $4) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 4))))
       ((position 5) (placeholder $5) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 6) (placeholder $6) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded one))))
       ((position 7) (placeholder $7) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 8) (placeholder $8) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded two))))
       ((position 9) (placeholder $9) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 10) (placeholder $10) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded one))))
       ((position 11) (placeholder $11) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 12) (placeholder $12) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded two))))
       ((position 13) (placeholder $13) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 14) (placeholder $14) (name (optional_mega_person_id))
        (db_type "option(int64)") (dialect_type (bigint)) (value (Null)))
       ((position 15) (placeholder $15) (name (optional_input_rows_limit))
        (db_type "option(int)") (dialect_type (integer)) (value ((Encoded 20))))
       ((position 16) (placeholder $16) (name (input_rows_offset))
        (db_type "option(int)") (dialect_type (integer)) (value ((Encoded 1))))
       ((position 17) (placeholder $17) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 18) (placeholder $18) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded one))))
       ((position 19) (placeholder $19) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 20) (placeholder $20) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded two))))
       ((position 21) (placeholder $21) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 22) (placeholder $22) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 101))))
       ((position 23) (placeholder $23) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded inserted))))
       ((position 24) (placeholder $24) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 102))))
       ((position 25) (placeholder $25) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded "also inserted"))))
       ((position 26) (placeholder $26) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 0))))
       ((position 27) (placeholder $27) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded " archived"))))
       ((position 28) (placeholder $28) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded expired))))
       ((position 29) (placeholder $29) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 0))))
       ((position 30) (placeholder $30) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 1))))
       ((position 31) (placeholder $31) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 0))))
       ((position 32) (placeholder $32) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 33) (placeholder $33) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 100))))
       ((position 34) (placeholder $34) (name (input_rows_limit)) (db_type int)
        (dialect_type (integer)) (value ((Encoded 20))))
       ((position 35) (placeholder $35) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 36) (placeholder $36) (name ()) (db_type "option(text)")
        (dialect_type (text)) (value (Null)))
       ((position 37) (placeholder $37) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded updated))))
       ((position 38) (placeholder $38) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 39) (placeholder $39) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 40) (placeholder $40) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded !))))
       ((position 41) (placeholder $41) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 42) (placeholder $42) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded one))))
       ((position 43) (placeholder $43) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 44) (placeholder $44) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded two))))
       ((position 45) (placeholder $45) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 46) (placeholder $46) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded one))))
       ((position 47) (placeholder $47) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 48) (placeholder $48) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded two))))
       ((position 49) (placeholder $49) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 50) (placeholder $50) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 51) (placeholder $51) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded one))))
       ((position 52) (placeholder $52) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 53) (placeholder $53) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded two))))
       ((position 54) (placeholder $54) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 55) (placeholder $55) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 1))))
       ((position 56) (placeholder $56) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 57) (placeholder $57) (name ()) (db_type float)
        (dialect_type ("double precision")) (value ((Encoded 1.5))))
       ((position 58) (placeholder $58) (name ()) (db_type numeric)
        (dialect_type (numeric)) (value ((Encoded 0.1234))))
       ((position 59) (placeholder $59) (name (mega_label)) (db_type text)
        (dialect_type (text)) (value ((Encoded mega))))
       ((position 60) (placeholder $60) (name ()) (db_type bytes)
        (dialect_type (bytea)) (value ((Encoded "\\x6d656761"))))
       ((position 61) (placeholder $61) (name ()) (db_type date)
        (dialect_type (date)) (value ((Encoded 2026-09-30))))
       ((position 62) (placeholder $62) (name ()) (db_type timestamp)
        (dialect_type ("timestamp with time zone"))
        (value ((Encoded 1970-01-01T00:00:00-00:00))))
       ((position 63) (placeholder $63) (name ()) (db_type uuid)
        (dialect_type (uuid))
        (value ((Encoded 550e8400-e29b-41d4-a716-446655440000))))
       ((position 64) (placeholder $64) (name ()) (db_type "option(mega_text)")
        (dialect_type (text)) (value ((Encoded mapped))))
       ((position 65) (placeholder $65) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 66) (placeholder $66) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 67) (placeholder $67) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 68) (placeholder $68) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 69) (placeholder $69) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 70) (placeholder $70) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 71) (placeholder $71) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 72) (placeholder $72) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 73) (placeholder $73) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 74) (placeholder $74) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 75) (placeholder $75) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 76) (placeholder $76) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 77) (placeholder $77) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 78) (placeholder $78) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 79) (placeholder $79) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded -1))))
       ((position 80) (placeholder $80) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded Ada))))
       ((position 81) (placeholder $81) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded Edsger))))
       ((position 82) (placeholder $82) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded unknown))))
       ((position 83) (placeholder $83) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 84) (placeholder $84) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1000))))
       ((position 85) (placeholder $85) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded ,))))
       ((position 86) (placeholder $86) (name ()) (db_type "option(text)")
        (dialect_type (text)) (value ((Encoded optional))))
       ((position 87) (placeholder $87) (name ()) (db_type "array_list(int64)")
        (dialect_type (bigint[])) (value ((Encoded "{\"1\"}"))))
       ((position 88) (placeholder $88) (name ())
        (db_type "timestamp without time zone")
        (dialect_type ("\"pg_catalog\".\"timestamp\""))
        (value ((Encoded "2026-09-30 12:34:56.000789"))))
       ((position 89) (placeholder $89) (name ()) (db_type interval)
        (dialect_type ("\"pg_catalog\".\"interval\""))
        (value ((Encoded "14 mons 3 days 4:05:06.000007"))))
       ((position 90) (placeholder $90) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 91) (placeholder $91) (name ()) (db_type "array(int64)")
        (dialect_type (bigint[])) (value ((Encoded "[0:1]={\"1\",NULL}"))))
       ((position 92) (placeholder $92) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 0))))
       ((position 93) (placeholder $93) (name ()) (db_type bool)
        (dialect_type (boolean)) (value ((Encoded true))))
       ((position 94) (placeholder $94) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 95) (placeholder $95) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 96) (placeholder $96) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 9))))
       ((position 97) (placeholder $97) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 98) (placeholder $98) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 99) (placeholder $99) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 100) (placeholder $100) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 101) (placeholder $101) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 100))))
       ((position 102) (placeholder $102) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 100))))
       ((position 103) (placeholder $103) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 104) (placeholder $104) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 100))))
       ((position 105) (placeholder $105) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 106) (placeholder $106) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 1))))
       ((position 107) (placeholder $107) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 2))))
       ((position 108) (placeholder $108) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded -1))))
       ((position 109) (placeholder $109) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 3))))
       ((position 110) (placeholder $110) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 4))))
       ((position 111) (placeholder $111) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 112) (placeholder $112) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 100))))
       ((position 113) (placeholder $113) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded different))))
       ((position 114) (placeholder $114) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded %v%))))
       ((position 115) (placeholder $115) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 0))))
       ((position 116) (placeholder $116) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 117) (placeholder $117) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded x))))
       ((position 118) (placeholder $118) (name ()) (db_type text)
        (dialect_type (text)) (value ((Encoded %))))
       ((position 119) (placeholder $119) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 120) (placeholder $120) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 121) (placeholder $121) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 122) (placeholder $122) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))
       ((position 123) (placeholder $123) (name ()) (db_type int)
        (dialect_type (integer)) (value ((Encoded 0))))
       ((position 124) (placeholder $124) (name ()) (db_type int64)
        (dialect_type (bigint)) (value ((Encoded 0))))))
     (output
      (Query_output (cardinality Many)
       (columns
        (((position 1) (name (id)) (db_type int64) (dialect_type (bigint)))
         ((position 2) (name (name)) (db_type text) (dialect_type (text)))
         ((position 3) (name ()) (db_type bool) (dialect_type (boolean)))
         ((position 4) (name ()) (db_type multiset) (dialect_type (jsonb)))
         ((position 5) (name ()) (db_type multiset) (dialect_type (jsonb)))
         ((position 6) (name ()) (db_type "option(int64)")
          (dialect_type (bigint)))))))
     (tree
      (Dialect_choice (selected (Postgresql))
       (postgresql (Leaf (kind Query) (mode Static)))
       (sqlite (Leaf (kind Query) (mode Static))))))
    |}]
;;

let%expect_test "SQLite choose_dialect branch compiles the shared output" =
  let sql, inspection =
    Statement.inspect_exn ~dialect:Sqlite ~input:([], 20, 1) statement
  in
  Stdlib.print_endline sql;
  [%expect
    {|
    SELECT
      t0."id",
      t0."name",
      (EXISTS (
        SELECT
          1
        FROM "mega_events" AS t1
        WHERE
          (t1."person_id" = t0."id")
      )),
      (
        SELECT
          COALESCE(
            JSON_GROUP_ARRAY(
              JSON_ARRAY(
                m0."v0",
                m0."v1",
                m0."v2"
              )
            ),
            JSON_ARRAY()
          )
        FROM (
          SELECT
            t1."id" AS "v0",
            t1."person_id" AS "v1",
            t1."label" AS "v2"
          FROM "mega_events" AS t1
          WHERE
            (t1."person_id" = t0."id")
          ORDER BY
            t1."id" ASC
          LIMIT 5
        ) AS m0
      ),
      (
        SELECT
          COALESCE(
            JSON_GROUP_ARRAY(
              JSON_ARRAY(
                JSON(m0."v0")
              )
            ),
            JSON_ARRAY()
          )
        FROM (
          SELECT
            JSON(COALESCE(
              JSON_GROUP_ARRAY(
                JSON_ARRAY(
                  t1."id",
                  t1."person_id",
                  t1."label",
                  JSON((
                    SELECT
                      COALESCE(
                        JSON_GROUP_ARRAY(
                          JSON_ARRAY(
                            m0."v0"
                          )
                        ),
                        JSON_ARRAY()
                      )
                    FROM (
                      SELECT
                        t2."id" AS "v0"
                      FROM "mega_events" AS t2
                      WHERE
                        (t2."person_id" = t0."id")
                    ) AS m0
                  )),
                  t1."happened_on",
                  t1."external_id",
                  t1."mapped_label"
                )
                ORDER BY t1."id" ASC
              ) FILTER (
                WHERE (
                  (t1."person_id" = t0."id")
                  AND ((EXISTS (
                    SELECT
                      1
                    FROM "mega_events" AS t2
                    WHERE
                      (
                        (t2."person_id" = t0."id")
                        AND (t2."value" > ?1)
                      )
                  )) = ?2)
                )
              ),
              JSON_ARRAY()
            )) AS "v0"
          FROM "mega_events" AS t1
        ) AS m0
      ),
      (
        SELECT
          COALESCE(SUM((CASE
            WHEN (
              (t1."id" = (t1."id" + ?3))
              AND ((t1."id" - ?4) = ?5)
              AND ((t1."id" * ?6) = t1."id")
              AND ((t1."id" / ?7) = t1."id")
              AND (t1."id" <> ?8)
              AND (t1."id" <> ?9)
              AND (t1."id" < ?10)
              AND (t1."id" <= ?11)
              AND (t1."id" >= ?12)
              AND (t1."id" <= ?13)
              AND (t1."id" >= ?14)
              AND (t1."nullable_id" IS NULL)
              AND (t1."nullable_id" IS NOT NULL)
              AND (t1."id" IN (
                ?15,
                ?16
              ))
              AND (t1."id" NOT IN (?17))
              AND (t1."id" IN (?18))
              AND (t1."id" NOT IN (?19))
              AND (t1."id" BETWEEN ?20 AND ?21)
              AND (t1."id" IN (
                SELECT
                  t2."id"
                FROM "mega_events" AS t2
                WHERE
                  (t2."id" = t1."id")
                LIMIT 1
              ))
              AND (t1."id" NOT IN (
                SELECT
                  t2."id"
                FROM "mega_events" AS t2
                WHERE
                  (t2."id" = t1."id")
                LIMIT 1
              ))
              AND (EXISTS (
                SELECT
                  1
                FROM "mega_events" AS t2
                WHERE
                  (t2."person_id" = t1."person_id")
              ))
              AND (NOT EXISTS (
                SELECT
                  1
                FROM "mega_events" AS t2
                WHERE
                  (t2."person_id" = t1."person_id")
              ))
              AND (t1."label" IS NOT ?22)
              AND (t1."label" LIKE ?23)
              AND (LENGTH(t1."label") > ?24)
              AND ((
                SELECT
                  t2."nullable_id"
                FROM "mega_events" AS t2
                WHERE
                  (t2."id" = t1."id")
                LIMIT 1
              ) = t1."id")
              AND (NOT (t1."id" > ?25))
              AND ((LOWER(t1."label") || ?26) LIKE ?27)
              AND (COALESCE(t1."nullable_id", ?28) > ?29)
              AND ((CASE
                WHEN TRUE THEN t1."id"
                ELSE ?30
              END) > ?31)
              AND (CURRENT_TIMESTAMP = CURRENT_TIMESTAMP)
            ) THEN t1."value"
            ELSE ?32
          END)), ?33)
        FROM "mega_events" AS t1
      )
    FROM "public"."mega_people" AS t0
    WHERE
      (
        (t0."name" = ?34)
        AND (EXISTS (
          SELECT
            1
          FROM (
            SELECT *
            FROM (
              SELECT
                t2."id" AS "id"
              FROM "public"."mega_people" AS t2
              WHERE
                (t2."name" = ?34)
            ) AS s0
            UNION
            SELECT *
            FROM (
              SELECT
                t2."id" AS "id"
              FROM "public"."mega_people" AS t2
              WHERE
                (t2."id" > ?35)
            ) AS s0
          ) AS t1
          WHERE
            (t1."id" = t0."id")
        ))
      )
    GROUP BY
      t0."id",
      t0."name"
    HAVING
      (COUNT(*) > ?36)
    LIMIT ?37
    OFFSET ?38
    |}];
  Stdlib.print_endline @@ Sexp.to_string_hum @@ Statement.sexp_of_inspection inspection;
  [%expect
    {|
    ((dialect Sqlite)
     (parameters
      (((position 1) (placeholder ?1) (name ()) (db_type int)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 2) (placeholder ?2) (name ()) (db_type bool)
        (dialect_type (INTEGER)) (value ((Encoded 1))))
       ((position 3) (placeholder ?3) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 1))))
       ((position 4) (placeholder ?4) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 1))))
       ((position 5) (placeholder ?5) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 9))))
       ((position 6) (placeholder ?6) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 1))))
       ((position 7) (placeholder ?7) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 1))))
       ((position 8) (placeholder ?8) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 9) (placeholder ?9) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 10) (placeholder ?10) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 100))))
       ((position 11) (placeholder ?11) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 100))))
       ((position 12) (placeholder ?12) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 13) (placeholder ?13) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 100))))
       ((position 14) (placeholder ?14) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 15) (placeholder ?15) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 1))))
       ((position 16) (placeholder ?16) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 2))))
       ((position 17) (placeholder ?17) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded -1))))
       ((position 18) (placeholder ?18) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 3))))
       ((position 19) (placeholder ?19) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 4))))
       ((position 20) (placeholder ?20) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 21) (placeholder ?21) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 100))))
       ((position 22) (placeholder ?22) (name ()) (db_type text)
        (dialect_type (TEXT)) (value ((Encoded different))))
       ((position 23) (placeholder ?23) (name ()) (db_type text)
        (dialect_type (TEXT)) (value ((Encoded %v%))))
       ((position 24) (placeholder ?24) (name ()) (db_type int)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 25) (placeholder ?25) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 26) (placeholder ?26) (name ()) (db_type text)
        (dialect_type (TEXT)) (value ((Encoded x))))
       ((position 27) (placeholder ?27) (name ()) (db_type text)
        (dialect_type (TEXT)) (value ((Encoded %))))
       ((position 28) (placeholder ?28) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 29) (placeholder ?29) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 30) (placeholder ?30) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 31) (placeholder ?31) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 32) (placeholder ?32) (name ()) (db_type int)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 33) (placeholder ?33) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 34) (placeholder ?34) (name (mega_label)) (db_type text)
        (dialect_type (TEXT)) (value ((Encoded mega))))
       ((position 35) (placeholder ?35) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 36) (placeholder ?36) (name ()) (db_type int64)
        (dialect_type (INTEGER)) (value ((Encoded 0))))
       ((position 37) (placeholder ?37) (name (input_rows_limit)) (db_type int)
        (dialect_type (INTEGER)) (value ((Encoded 20))))
       ((position 38) (placeholder ?38) (name (input_rows_offset)) (db_type int)
        (dialect_type (INTEGER)) (value ((Encoded 1))))))
     (output
      (Query_output (cardinality Many)
       (columns
        (((position 1) (name (id)) (db_type int64) (dialect_type ()))
         ((position 2) (name (name)) (db_type text) (dialect_type ()))
         ((position 3) (name ()) (db_type bool) (dialect_type ()))
         ((position 4) (name ()) (db_type multiset) (dialect_type ()))
         ((position 5) (name ()) (db_type multiset) (dialect_type ()))
         ((position 6) (name ()) (db_type "option(int64)") (dialect_type ()))))))
     (tree
      (Dialect_choice (selected (Sqlite))
       (postgresql (Leaf (kind Query) (mode Static)))
       (sqlite (Leaf (kind Query) (mode Static))))))
    |}]
;;

let%expect_test "PostgreSQL choose_dialect branch rejects negative pagination" =
  (match Statement.sql_exn ~dialect:Postgresql ~input:([], -1, 1) statement with
   | exception
       Statement.Sql_error
         (Statement.Invalid_parameter
            { name = Some name; message = Statement.Negative_pagination_value value }) ->
     Stdlib.print_endline
       (Stdlib.Printf.sprintf "%s must be non-negative, got %d" name value)
   | _ -> failwith "negative pagination value unexpectedly rendered SQL");
  [%expect {| optional_input_rows_limit must be non-negative, got -1 |}]
;;

let%expect_test "SQLite choose_dialect branch rejects negative pagination" =
  (match Statement.sql_exn ~dialect:Sqlite ~input:([], -1, 1) statement with
   | exception
       Statement.Sql_error
         (Statement.Invalid_parameter
            { name = Some name; message = Statement.Negative_pagination_value value }) ->
     Stdlib.print_endline
       (Stdlib.Printf.sprintf "%s must be non-negative, got %d" name value)
   | _ -> failwith "negative pagination value unexpectedly rendered SQL");
  [%expect {|input_rows_limit must be non-negative, got -1|}]
;;
