open! Base
module Typed_sql_codegen = Typed_sql
module Typed_sql_codegen_ptime = Ptime

module Typed_sql_generated_types = struct
  module Type_public_mood = struct
    type t =
      | Happy
      | Sad

    let encode = function
      | Happy -> Ok "happy"
      | Sad -> Ok "sad"
    ;;

    let decode = function
      | "happy" -> Ok Happy
      | "sad" -> Ok Sad
      | _ -> Error "unknown enum label"
    ;;

    let db_type =
      Typed_sql_codegen.Db_type.map
        ~name:"public.mood"
        ~encode
        ~decode
        (Typed_sql_codegen.Db_type.Postgresql.named
           ~schema:(Typed_sql_codegen.Identifier.of_string_exn "public")
           ~name:(Typed_sql_codegen.Identifier.of_string_exn "mood")
           Typed_sql_codegen.Db_type.text)
    ;;
  end

  module Type_public_username : sig
    type t

    val of_base : string -> t
    val to_base : t -> string
    val db_type : t Typed_sql_codegen.Db_type.t
  end = struct
    type t = Value of string

    let of_base value = Value value
    let to_base (Value value) = value

    let db_type =
      Typed_sql_codegen.Db_type.map
        ~name:"public.username"
        ~encode:(fun value -> Ok (to_base value))
        ~decode:(fun value -> Ok (of_base value))
        (Typed_sql_codegen.Db_type.Postgresql.named
           ~schema:(Typed_sql_codegen.Identifier.of_string_exn "public")
           ~name:(Typed_sql_codegen.Identifier.of_string_exn "username")
           Typed_sql_codegen.Db_type.text)
    ;;
  end

  module Type_public_host : sig
    type t

    val of_base : Schema_test_codecs.Inet.t -> t
    val to_base : t -> Schema_test_codecs.Inet.t
    val db_type : t Typed_sql_codegen.Db_type.t
  end = struct
    type t = Value of Schema_test_codecs.Inet.t

    let of_base value = Value value
    let to_base (Value value) = value

    let db_type =
      Typed_sql_codegen.Db_type.map
        ~name:"public.host"
        ~encode:(fun value -> Ok (to_base value))
        ~decode:(fun value -> Ok (of_base value))
        (Typed_sql_codegen.Db_type.Postgresql.named
           ~schema:(Typed_sql_codegen.Identifier.of_string_exn "public")
           ~name:(Typed_sql_codegen.Identifier.of_string_exn "host")
           Schema_test_codecs.Inet.db_type)
    ;;
  end
end

module User_profile = struct
  type row
  type t = { id : int64 }

  let table : row Typed_sql_codegen.Table.t =
    Typed_sql_codegen.Table.v_exn ~schema:"public" "USER PROFILE"
  ;;

  let id_column =
    Typed_sql_codegen.Column.v_exn table "id" Typed_sql_codegen.Db_type.int64
  ;;

  let id table_ref = Typed_sql_codegen.Expr.column table_ref id_column
  let id_has_default = false
  let id_default = None
  let id_is_generated = false
  let id_primary_key_position = None
  let foreign_keys = []
  let unique_constraints = []

  let projection table_ref =
    let open Typed_sql_codegen.Projection.Let_syntax in
    let%map id = Typed_sql_codegen.Projection.expr (id table_ref) in
    { id }
  ;;
end

module Advanced = struct
  type row

  type t =
    { local_value : Typed_sql_codegen.Local_timestamp.t
    ; float_value : Schema_test_codecs.Local_float.t
    ; duration : Typed_sql_codegen.Interval.t
    ; payload : Yojson.Safe.t
    ; payload_binary : Yojson.Safe.t
    ; mood : Typed_sql_generated_types.Type_public_mood.t
    ; username : Typed_sql_generated_types.Type_public_username.t
    ; host : Typed_sql_generated_types.Type_public_host.t
    ; inet_value : Schema_test_codecs.Inet.t
    ; small_value : Schema_test_codecs.Small_int.t
    ; numbers : int Typed_sql_codegen.Pg_array.t
    ; rational_value : Schema_test_codecs.Rational.t
    ; geometry_value : Schema_test_codecs.Geometry.t
    }

  let table : row Typed_sql_codegen.Table.t =
    Typed_sql_codegen.Table.v_exn ~schema:"public" "advanced"
  ;;

  let local_value_column =
    Typed_sql_codegen.Column.v_exn
      table
      "local_value"
      Typed_sql_codegen.Db_type.Postgresql.local_timestamp
  ;;

  let local_value table_ref = Typed_sql_codegen.Expr.column table_ref local_value_column
  let local_value_has_default = false
  let local_value_default = None
  let local_value_is_generated = false
  let local_value_primary_key_position = None

  let float_value_column =
    Typed_sql_codegen.Column.v_exn
      table
      "float_value"
      Schema_test_codecs.Local_float.db_type
  ;;

  let float_value table_ref = Typed_sql_codegen.Expr.column table_ref float_value_column
  let float_value_has_default = false
  let float_value_default = None
  let float_value_is_generated = false
  let float_value_primary_key_position = None

  let duration_column =
    Typed_sql_codegen.Column.v_exn
      table
      "duration"
      Typed_sql_codegen.Db_type.Postgresql.interval
  ;;

  let duration table_ref = Typed_sql_codegen.Expr.column table_ref duration_column
  let duration_has_default = false
  let duration_default = None
  let duration_is_generated = false
  let duration_primary_key_position = None

  let payload_column =
    Typed_sql_codegen.Column.v_exn
      table
      "payload"
      Typed_sql_codegen.Db_type.Postgresql.json
  ;;

  let payload table_ref = Typed_sql_codegen.Expr.column table_ref payload_column
  let payload_has_default = false
  let payload_default = None
  let payload_is_generated = false
  let payload_primary_key_position = None

  let payload_binary_column =
    Typed_sql_codegen.Column.v_exn
      table
      "payload_binary"
      Typed_sql_codegen.Db_type.Postgresql.jsonb
  ;;

  let payload_binary table_ref =
    Typed_sql_codegen.Expr.column table_ref payload_binary_column
  ;;

  let payload_binary_has_default = false
  let payload_binary_default = None
  let payload_binary_is_generated = false
  let payload_binary_primary_key_position = None

  let mood_column =
    Typed_sql_codegen.Column.v_exn
      table
      "mood"
      Typed_sql_generated_types.Type_public_mood.db_type
  ;;

  let mood table_ref = Typed_sql_codegen.Expr.column table_ref mood_column
  let mood_has_default = false
  let mood_default = None
  let mood_is_generated = false
  let mood_primary_key_position = None

  let username_column =
    Typed_sql_codegen.Column.v_exn
      table
      "username"
      Typed_sql_generated_types.Type_public_username.db_type
  ;;

  let username table_ref = Typed_sql_codegen.Expr.column table_ref username_column
  let username_has_default = false
  let username_default = None
  let username_is_generated = false
  let username_primary_key_position = None

  let host_column =
    Typed_sql_codegen.Column.v_exn
      table
      "host"
      Typed_sql_generated_types.Type_public_host.db_type
  ;;

  let host table_ref = Typed_sql_codegen.Expr.column table_ref host_column
  let host_has_default = false
  let host_default = None
  let host_is_generated = false
  let host_primary_key_position = None

  let inet_value_column =
    Typed_sql_codegen.Column.v_exn table "inet_value" Schema_test_codecs.Inet.db_type
  ;;

  let inet_value table_ref = Typed_sql_codegen.Expr.column table_ref inet_value_column
  let inet_value_has_default = false
  let inet_value_default = None
  let inet_value_is_generated = false
  let inet_value_primary_key_position = None

  let small_value_column =
    Typed_sql_codegen.Column.v_exn
      table
      "small_value"
      Schema_test_codecs.Small_int.db_type
  ;;

  let small_value table_ref = Typed_sql_codegen.Expr.column table_ref small_value_column
  let small_value_has_default = false
  let small_value_default = None
  let small_value_is_generated = false
  let small_value_primary_key_position = None

  let numbers_column =
    Typed_sql_codegen.Column.v_exn
      table
      "numbers"
      (Typed_sql_codegen.Db_type.Postgresql.array Typed_sql_codegen.Db_type.int)
  ;;

  let numbers table_ref = Typed_sql_codegen.Expr.column table_ref numbers_column
  let numbers_has_default = false
  let numbers_default = None
  let numbers_is_generated = false
  let numbers_primary_key_position = None

  let rational_value_column =
    Typed_sql_codegen.Column.v_exn
      table
      "rational_value"
      Schema_test_codecs.Rational.db_type
  ;;

  let rational_value table_ref =
    Typed_sql_codegen.Expr.column table_ref rational_value_column
  ;;

  let rational_value_has_default = false
  let rational_value_default = None
  let rational_value_is_generated = false
  let rational_value_primary_key_position = None

  let geometry_value_column =
    Typed_sql_codegen.Column.v_exn
      table
      "geometry_value"
      Schema_test_codecs.Geometry.db_type
  ;;

  let geometry_value table_ref =
    Typed_sql_codegen.Expr.column table_ref geometry_value_column
  ;;

  let geometry_value_has_default = false
  let geometry_value_default = None
  let geometry_value_is_generated = false
  let geometry_value_primary_key_position = None
  let foreign_keys = []
  let unique_constraints = []

  let projection table_ref =
    let open Typed_sql_codegen.Projection.Let_syntax in
    let%map local_value = Typed_sql_codegen.Projection.expr (local_value table_ref)
    and float_value = Typed_sql_codegen.Projection.expr (float_value table_ref)
    and duration = Typed_sql_codegen.Projection.expr (duration table_ref)
    and payload = Typed_sql_codegen.Projection.expr (payload table_ref)
    and payload_binary = Typed_sql_codegen.Projection.expr (payload_binary table_ref)
    and mood = Typed_sql_codegen.Projection.expr (mood table_ref)
    and username = Typed_sql_codegen.Projection.expr (username table_ref)
    and host = Typed_sql_codegen.Projection.expr (host table_ref)
    and inet_value = Typed_sql_codegen.Projection.expr (inet_value table_ref)
    and small_value = Typed_sql_codegen.Projection.expr (small_value table_ref)
    and numbers = Typed_sql_codegen.Projection.expr (numbers table_ref)
    and rational_value = Typed_sql_codegen.Projection.expr (rational_value table_ref)
    and geometry_value = Typed_sql_codegen.Projection.expr (geometry_value table_ref) in
    { local_value
    ; float_value
    ; duration
    ; payload
    ; payload_binary
    ; mood
    ; username
    ; host
    ; inet_value
    ; small_value
    ; numbers
    ; rational_value
    ; geometry_value
    }
  ;;
end

module Table = struct
  type row
  type t = { id : int64 }

  let table : row Typed_sql_codegen.Table.t =
    Typed_sql_codegen.Table.v_exn ~schema:"public" "table"
  ;;

  let id_column =
    Typed_sql_codegen.Column.v_exn table "id" Typed_sql_codegen.Db_type.int64
  ;;

  let id table_ref = Typed_sql_codegen.Expr.column table_ref id_column
  let id_has_default = false
  let id_default = None
  let id_is_generated = false
  let id_primary_key_position = None
  let foreign_keys = []
  let unique_constraints = []

  let projection table_ref =
    let open Typed_sql_codegen.Projection.Let_syntax in
    let%map id = Typed_sql_codegen.Projection.expr (id table_ref) in
    { id }
  ;;
end

module Typed_sql_codegen_2 = struct
  type row
  type t = { id : int64 }

  let table : row Typed_sql_codegen.Table.t =
    Typed_sql_codegen.Table.v_exn ~schema:"public" "typed_sql_codegen"
  ;;

  let id_column =
    Typed_sql_codegen.Column.v_exn table "id" Typed_sql_codegen.Db_type.int64
  ;;

  let id table_ref = Typed_sql_codegen.Expr.column table_ref id_column
  let id_has_default = false
  let id_default = None
  let id_is_generated = false
  let id_primary_key_position = None
  let foreign_keys = []
  let unique_constraints = []

  let projection table_ref =
    let open Typed_sql_codegen.Projection.Let_syntax in
    let%map id = Typed_sql_codegen.Projection.expr (id table_ref) in
    { id }
  ;;
end

module User_profile_2 = struct
  type row

  type t =
    { id : int64
    ; id_column_2 : int
    ; display_name : string
    ; display_name_2 : string
    ; display_name_3 : string
    ; table_2 : bool
    ; published_on : Typed_sql_codegen.Date.t
    ; created_at : Typed_sql_codegen_ptime.t
    ; external_id : Typed_sql_codegen.Uuid.t
    ; reference : string
    ; return_2 : string
    ; land_ : string
    ; field : string
    ; map_2 : string
    ; total : Typed_sql_codegen.Decimal.t
    }

  let table : row Typed_sql_codegen.Table.t =
    Typed_sql_codegen.Table.v_exn ~schema:"public" "user-profile"
  ;;

  let id_column =
    Typed_sql_codegen.Column.v_exn table "id" Typed_sql_codegen.Db_type.int64
  ;;

  let id table_ref = Typed_sql_codegen.Expr.column table_ref id_column
  let id_has_default = false
  let id_default = None
  let id_is_generated = false
  let id_primary_key_position = None

  let id_column_2_column =
    Typed_sql_codegen.Column.v_exn table "id-column" Typed_sql_codegen.Db_type.int
  ;;

  let id_column_2 table_ref = Typed_sql_codegen.Expr.column table_ref id_column_2_column
  let id_column_2_has_default = false
  let id_column_2_default = None
  let id_column_2_is_generated = false
  let id_column_2_primary_key_position = None

  let display_name_column =
    Typed_sql_codegen.Column.v_exn table "display-name" Typed_sql_codegen.Db_type.text
  ;;

  let display_name table_ref = Typed_sql_codegen.Expr.column table_ref display_name_column
  let display_name_has_default = false
  let display_name_default = None
  let display_name_is_generated = false
  let display_name_primary_key_position = None

  let display_name_2_column =
    Typed_sql_codegen.Column.v_exn table "display_name" Typed_sql_codegen.Db_type.text
  ;;

  let display_name_2 table_ref =
    Typed_sql_codegen.Expr.column table_ref display_name_2_column
  ;;

  let display_name_2_has_default = false
  let display_name_2_default = None
  let display_name_2_is_generated = false
  let display_name_2_primary_key_position = None

  let display_name_3_column =
    Typed_sql_codegen.Column.v_exn table "display.name" Typed_sql_codegen.Db_type.text
  ;;

  let display_name_3 table_ref =
    Typed_sql_codegen.Expr.column table_ref display_name_3_column
  ;;

  let display_name_3_has_default = false
  let display_name_3_default = None
  let display_name_3_is_generated = false
  let display_name_3_primary_key_position = None

  let table_2_column =
    Typed_sql_codegen.Column.v_exn table "table" Typed_sql_codegen.Db_type.bool
  ;;

  let table_2 table_ref = Typed_sql_codegen.Expr.column table_ref table_2_column
  let table_2_has_default = false
  let table_2_default = None
  let table_2_is_generated = false
  let table_2_primary_key_position = None

  let published_on_column =
    Typed_sql_codegen.Column.v_exn table "published-on" Typed_sql_codegen.Db_type.date
  ;;

  let published_on table_ref = Typed_sql_codegen.Expr.column table_ref published_on_column
  let published_on_has_default = false
  let published_on_default = None
  let published_on_is_generated = false
  let published_on_primary_key_position = None

  let created_at_column =
    Typed_sql_codegen.Column.v_exn table "created-at" Typed_sql_codegen.Db_type.timestamp
  ;;

  let created_at table_ref = Typed_sql_codegen.Expr.column table_ref created_at_column
  let created_at_has_default = false
  let created_at_default = None
  let created_at_is_generated = false
  let created_at_primary_key_position = None

  let external_id_column =
    Typed_sql_codegen.Column.v_exn table "external-id" Typed_sql_codegen.Db_type.uuid
  ;;

  let external_id table_ref = Typed_sql_codegen.Expr.column table_ref external_id_column
  let external_id_has_default = false
  let external_id_default = None
  let external_id_is_generated = false
  let external_id_primary_key_position = None

  let reference_column =
    Typed_sql_codegen.Column.v_exn table "reference" Typed_sql_codegen.Db_type.text
  ;;

  let reference table_ref = Typed_sql_codegen.Expr.column table_ref reference_column
  let reference_has_default = false
  let reference_default = None
  let reference_is_generated = false
  let reference_primary_key_position = None

  let return_2_column =
    Typed_sql_codegen.Column.v_exn table "return" Typed_sql_codegen.Db_type.text
  ;;

  let return_2 table_ref = Typed_sql_codegen.Expr.column table_ref return_2_column
  let return_2_has_default = false
  let return_2_default = None
  let return_2_is_generated = false
  let return_2_primary_key_position = None

  let land__column =
    Typed_sql_codegen.Column.v_exn table "land" Typed_sql_codegen.Db_type.text
  ;;

  let land_ table_ref = Typed_sql_codegen.Expr.column table_ref land__column
  let land__has_default = false
  let land__default = None
  let land__is_generated = false
  let land__primary_key_position = None

  let field_column =
    Typed_sql_codegen.Column.v_exn table "_" Typed_sql_codegen.Db_type.text
  ;;

  let field table_ref = Typed_sql_codegen.Expr.column table_ref field_column
  let field_has_default = false
  let field_default = None
  let field_is_generated = false
  let field_primary_key_position = None

  let map_2_column =
    Typed_sql_codegen.Column.v_exn table "map" Typed_sql_codegen.Db_type.text
  ;;

  let map_2 table_ref = Typed_sql_codegen.Expr.column table_ref map_2_column
  let map_2_has_default = false
  let map_2_default = None
  let map_2_is_generated = false
  let map_2_primary_key_position = None

  let total_column =
    Typed_sql_codegen.Column.v_exn table "total" Typed_sql_codegen.Db_type.numeric
  ;;

  let total table_ref = Typed_sql_codegen.Expr.column table_ref total_column
  let total_has_default = false
  let total_default = None
  let total_is_generated = false
  let total_primary_key_position = None
  let foreign_keys = []
  let unique_constraints = []

  let projection table_ref =
    let open Typed_sql_codegen.Projection.Let_syntax in
    let%map id = Typed_sql_codegen.Projection.expr (id table_ref)
    and id_column_2 = Typed_sql_codegen.Projection.expr (id_column_2 table_ref)
    and display_name = Typed_sql_codegen.Projection.expr (display_name table_ref)
    and display_name_2 = Typed_sql_codegen.Projection.expr (display_name_2 table_ref)
    and display_name_3 = Typed_sql_codegen.Projection.expr (display_name_3 table_ref)
    and table_2 = Typed_sql_codegen.Projection.expr (table_2 table_ref)
    and published_on = Typed_sql_codegen.Projection.expr (published_on table_ref)
    and created_at = Typed_sql_codegen.Projection.expr (created_at table_ref)
    and external_id = Typed_sql_codegen.Projection.expr (external_id table_ref)
    and reference = Typed_sql_codegen.Projection.expr (reference table_ref)
    and return_2 = Typed_sql_codegen.Projection.expr (return_2 table_ref)
    and land_ = Typed_sql_codegen.Projection.expr (land_ table_ref)
    and field = Typed_sql_codegen.Projection.expr (field table_ref)
    and map_2 = Typed_sql_codegen.Projection.expr (map_2 table_ref)
    and total = Typed_sql_codegen.Projection.expr (total table_ref) in
    { id
    ; id_column_2
    ; display_name
    ; display_name_2
    ; display_name_3
    ; table_2
    ; published_on
    ; created_at
    ; external_id
    ; reference
    ; return_2
    ; land_
    ; field
    ; map_2
    ; total
    }
  ;;
end

module User_profile_3 = struct
  type row
  type t = { id : int64 }

  let table : row Typed_sql_codegen.Table.t =
    Typed_sql_codegen.Table.v_exn ~schema:"public" "user_profile"
  ;;

  let id_column =
    Typed_sql_codegen.Column.v_exn table "id" Typed_sql_codegen.Db_type.int64
  ;;

  let id table_ref = Typed_sql_codegen.Expr.column table_ref id_column
  let id_has_default = false
  let id_default = None
  let id_is_generated = false
  let id_primary_key_position = None
  let foreign_keys = []
  let unique_constraints = []

  let projection table_ref =
    let open Typed_sql_codegen.Projection.Let_syntax in
    let%map id = Typed_sql_codegen.Projection.expr (id table_ref) in
    { id }
  ;;
end
