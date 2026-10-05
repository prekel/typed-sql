open! Base

type definition_error =
  { dialect : Dialect.t
  ; error : Compile_error.t
  }
[@@deriving sexp_of]

exception Definition_error of definition_error

let () =
  Stdlib.Printexc.register_printer (function
    | Definition_error { dialect; error } ->
      Some
        (Stdlib.Printf.sprintf
           "Statement.Definition_error (%s): %s"
           (Dialect.to_string dialect)
           (Compile_error.to_string error))
    | _ -> None)
;;

type binding_error_message =
  | Unknown_parameter_slot
  | Negative_pagination_value of int
[@@deriving sexp_of]

type binding_error =
  { name : string option
  ; message : binding_error_message
  }
[@@deriving sexp_of]

type sql_error =
  | Unsupported_dialect of Dialect.t
  | Dynamic_input_required
  | Invalid_parameter of binding_error
  | Compilation_error of definition_error
[@@deriving sexp_of]

type parameter_value =
  | Null
  | Encoded of string
[@@deriving sexp_of]

type parameter =
  { position : int
  ; placeholder : string
  ; name : string option
  ; db_type : string
  ; dialect_type : string option
  ; value : parameter_value option
  }
[@@deriving sexp_of]

type output_column =
  { position : int
  ; name : string option
  ; db_type : string
  ; dialect_type : string option
  }
[@@deriving sexp_of]

type row_cardinality =
  [ `Many
  | `One
  | `Optional
  ]
[@@deriving sexp_of]

type output =
  | Query_output of
      { cardinality : row_cardinality
      ; columns : output_column list
      }
  | Command_output
[@@deriving sexp_of]

type statement_kind =
  [ `Query
  | `Command
  ]
[@@deriving sexp_of]

type statement_mode =
  [ `Static
  | `Dynamic
  ]
[@@deriving sexp_of]

type statement_tree =
  | Leaf of
      { kind : statement_kind
      ; mode : statement_mode
      }
  | Input_choice of
      { selected : bool option
      ; if_true : statement_tree
      ; if_false : statement_tree
      }
  | Dialect_choice of
      { selected : Dialect.t option
      ; postgresql : statement_tree
      ; sqlite : statement_tree
      }
[@@deriving sexp_of]

type inspection =
  { dialect : Dialect.t
  ; parameters : parameter list
  ; output : output
  ; tree : statement_tree
  }
[@@deriving sexp_of]

type inspection_error =
  | Statement_error of sql_error
  | Codec_error of
      { position : int
      ; name : string option
      ; message : string
      }
[@@deriving sexp_of]

exception Sql_error of sql_error
exception Inspection_error of inspection_error

let () =
  let binding_error_message_to_string = function
    | Unknown_parameter_slot -> "unknown parameter slot"
    | Negative_pagination_value value ->
      Stdlib.Printf.sprintf "must be non-negative, got %d" value
  in
  Stdlib.Printexc.register_printer (function
    | Sql_error (Unsupported_dialect dialect) ->
      Some
        (Stdlib.Printf.sprintf
           "Statement.Sql_error (unsupported dialect: %s)"
           (Dialect.to_string dialect))
    | Sql_error Dynamic_input_required ->
      Some "Statement.Sql_error (SQL shape requires input)"
    | Sql_error (Invalid_parameter { name; message }) ->
      let name = Option.value name ~default:"parameter" in
      Some
        (Stdlib.Printf.sprintf
           "Statement.Sql_error (%s: %s)"
           name
           (binding_error_message_to_string message))
    | Sql_error (Compilation_error { dialect; error }) ->
      Some
        (Stdlib.Printf.sprintf
           "Statement.Sql_error (%s): %s"
           (Dialect.to_string dialect)
           (Compile_error.to_string error))
    | Inspection_error error ->
      Some
        (Stdlib.Printf.sprintf
           "Statement.Inspection_error %s"
           (Sexp.to_string_hum (sexp_of_inspection_error error)))
    | _ -> None)
;;

type 'input slot =
  | Slot :
      { id : int
      ; name : string option
      ; db_type : 'value Db_type.t
      ; get : 'input -> 'value
      ; validate : 'value -> binding_error_message option
      }
      -> 'input slot

type (_, _) cardinality =
  | Many : ('row, 'row list) cardinality
  | One : ('row, 'row) cardinality
  | Optional : ('row, 'row option) cardinality

type ('input, 'row) query_plan =
  { compiled : 'row Compiler.query_plan
  ; slots : 'input slot list
  }

type 'input command_plan =
  { compiled : Compiler.command_plan
  ; slots : 'input slot list
  }

type ('plan, 'supports) plan_set =
  | Postgresql_plan : 'plan -> ('plan, [ `Postgresql ]) plan_set
  | Sqlite_plan : 'plan -> ('plan, [ `Sqlite ]) plan_set
  | Portable_plans :
      { postgresql_plan : 'plan
      ; sqlite_plan : 'plan
      }
      -> ('plan, Dialect.both) plan_set

type ('input, 'output, 'supports) t =
  | Dynamic_query :
      { cardinality : ('row, 'output) cardinality
      ; dialect : ('requirements, 'supports) Dialect.supports
      ; build : 'input -> ('row, 'kind, 'query_cardinality, 'requirements) Result_query.t
      }
      -> ('input, 'output, 'supports) t
  | Dynamic_command :
      { dialect : ('requirements, 'supports) Dialect.supports
      ; build : 'input -> 'requirements Command.t
      }
      -> ('input, Affected_rows.t, 'supports) t
  | Query :
      { cardinality : ('row, 'output) cardinality
      ; plans : (('input, 'row) query_plan, 'supports) plan_set
      }
      -> ('input, 'output, 'supports) t
  | Command :
      { plans : ('input command_plan, 'supports) plan_set }
      -> ('input, Affected_rows.t, 'supports) t
  | Choose :
      { when_ : 'input -> bool
      ; if_true : ('input, 'output, 'supports) t
      ; if_false : ('input, 'output, 'supports) t
      }
      -> ('input, 'output, 'supports) t
  | Choose_dialect :
      { postgresql : ('input, 'output, [ `Postgresql ]) t
      ; sqlite : ('input, 'output, [ `Sqlite ]) t
      }
      -> ('input, 'output, Dialect.both) t

and ('input, 'requirements, 'supports) parameters =
  { expr :
      'value.
      ?name:string
      -> 'value Db_type.t
      -> get:('input -> 'value)
      -> ('input, 'requirements, ('value, 'requirements) Expr.t) Parameters.t
  ; optional_expr :
      'value.
      ?name:string
      -> 'value Db_type.t
      -> get:('input -> 'value option)
      -> ( 'input
           , 'requirements
           , ('value, 'requirements) Optional_parameter.t )
           Parameters.t
  ; column :
      'row 'base 'value.
      ?name:string
      -> ('row, 'base, 'value) Column.t
      -> get:('input -> 'value)
      -> ('input, 'requirements, ('value, 'requirements) Expr.t) Parameters.t
  ; non_negative_int :
      name:string
      -> get:('input -> int)
      -> ('input, 'requirements, 'requirements Pagination_parameter.t) Parameters.t
  ; non_negative_int_opt :
      name:string
      -> get:('input -> int option)
      -> ('input, 'requirements, 'requirements Pagination_parameter.optional) Parameters.t
  ; query_many :
      'row 'kind 'cardinality.
      ('row, 'kind, 'cardinality, 'requirements) Result_query.t
      -> ('input, 'row list, 'supports) t
  ; query_one :
      'row 'kind 'cardinality.
      ('row, 'kind, ([> `Exactly_one ] as 'cardinality), 'requirements) Result_query.t
      -> ('input, 'row, 'supports) t
  ; query_optional :
      'row 'kind 'cardinality.
      ('row, 'kind, ([> `At_most_one ] as 'cardinality), 'requirements) Result_query.t
      -> ('input, 'row option, 'supports) t
  ; expect_one :
      'row 'kind 'cardinality.
      ('row, 'kind, 'cardinality, 'requirements) Result_query.t
      -> ('input, 'row, 'supports) t
  ; expect_optional :
      'row 'kind 'cardinality.
      ('row, 'kind, 'cardinality, 'requirements) Result_query.t
      -> ('input, 'row option, 'supports) t
  ; command : 'requirements Command.t -> ('input, Affected_rows.t, 'supports) t
  }

type 'output execution =
  | Query_execution :
      { cardinality : ('row, 'output) cardinality
      ; compiled : 'row Compiled_query.t
      }
      -> 'output execution
  | Command_execution : Compiled_command.t -> Affected_rows.t execution

type bound_parameter =
  { packed_value : Db_type.packed_value
  ; name : string option
  }

type 'output resolved_plan =
  | Resolved_query :
      { cardinality : ('row, 'output) cardinality
      ; compiled : 'row Compiler.query_plan
      ; parameters : bound_parameter list
      }
      -> 'output resolved_plan
  | Resolved_command :
      { compiled : Compiler.command_plan
      ; parameters : bound_parameter list
      }
      -> Affected_rows.t resolved_plan

type resolve_error =
  | Dialect_mismatch
  | Binding of binding_error
  | Compilation of definition_error

let next_slot = Atomic.make 0
let definition_error dialect error = { dialect; error }

let compile_query ~dialect slots query =
  Compiler.compile_query_plan ~dialect query
  |> Result.map ~f:(fun compiled ->
    ({ compiled; slots = List.rev !slots } : (_, _) query_plan))
  |> Result.map_error ~f:(definition_error dialect)
;;

let compile_command ~dialect slots command =
  Compiler.compile_command_plan ~dialect command
  |> Result.map ~f:(fun compiled ->
    ({ compiled; slots = List.rev !slots } : _ command_plan))
  |> Result.map_error ~f:(definition_error dialect)
;;

let or_raise = function
  | Ok statement -> statement
  | Error error -> raise (Definition_error error)
;;

let compile_with_witness
  : type requirements supports value error.
    (requirements, supports) Dialect.supports
    -> (Dialect.t -> (value, error) Result.t)
    -> ((value, supports) plan_set, error) Result.t
  =
  fun witness compile ->
  match witness with
  | Dialect.Portable ->
    let open Result.Let_syntax in
    let%bind postgresql_plan = compile Dialect.Postgresql in
    let%map sqlite_plan = compile Dialect.Sqlite in
    Portable_plans { postgresql_plan; sqlite_plan }
  | Dialect.Concrete_postgresql ->
    Result.map (compile Dialect.Postgresql) ~f:(fun plan -> Postgresql_plan plan)
  | Dialect.Concrete_sqlite ->
    Result.map (compile Dialect.Sqlite) ~f:(fun plan -> Sqlite_plan plan)
;;

let compile_scoped_query ~dialect ~cardinality slots query =
  compile_with_witness dialect (fun dialect -> compile_query ~dialect slots query)
  |> Result.map ~f:(fun plans -> Query { cardinality; plans })
;;

let compile_scoped_command ~dialect slots command =
  compile_with_witness dialect (fun dialect -> compile_command ~dialect slots command)
  |> Result.map ~f:(fun plans -> Command { plans })
;;

let make_parameters ~dialect slots =
  let register ?name ?(validate = fun _ -> None) db_type ~get =
    let id = Atomic.fetch_and_add next_slot 1 in
    let parameter = Ast.Slot { id; db_type = Db_type.Pack db_type } in
    slots := Slot { id; name; db_type; get; validate } :: !slots;
    parameter
  in
  let make_expr
    : type value.
      ?name:string
      -> value Db_type.t
      -> get:('input -> value)
      -> (value, 'requirements) Expr.t
    =
    fun ?name db_type ~get ->
    let parameter = register ?name db_type ~get in
    Expr.create (Ast.Param parameter) db_type
  in
  let expr ?name db_type ~get = Parameters.return (make_expr ?name db_type ~get) in
  let make_optional_expr ?name db_type ~get =
    let nullable_expr = make_expr ?name (Db_type.option db_type) ~get in
    let value_expr = Expr.create (Expr.node nullable_expr) db_type in
    Optional_parameter.create nullable_expr value_expr
  in
  let optional_expr ?name db_type ~get =
    Parameters.return (make_optional_expr ?name db_type ~get)
  in
  let column
    : type row base value.
      ?name:string
      -> (row, base, value) Column.t
      -> get:('input -> value)
      -> ('input, 'requirements, (value, 'requirements) Expr.t) Parameters.t
    =
    fun ?name column ~get ->
    let name = Option.value name ~default:(Identifier.to_string (Column.name column)) in
    Parameters.return (make_expr ~name (Column.db_type column) ~get)
  in
  let make_non_negative_int ~name ~get =
    let validate value =
      if value < 0 then
        Some (Negative_pagination_value value)
      else
        None
    in
    register ~name ~validate Db_type.int ~get |> Pagination_parameter.create
  in
  let non_negative_int ~name ~get =
    Parameters.return (make_non_negative_int ~name ~get)
  in
  let make_non_negative_int_opt ~name ~get =
    let validate = function
      | Some value when value < 0 -> Some (Negative_pagination_value value)
      | None | Some _ -> None
    in
    register ~name ~validate (Db_type.option Db_type.int) ~get
    |> Pagination_parameter.create_optional
  in
  let non_negative_int_opt ~name ~get =
    Parameters.return (make_non_negative_int_opt ~name ~get)
  in
  let query_many query =
    compile_scoped_query ~dialect ~cardinality:Many slots query |> or_raise
  in
  let query_one query =
    compile_scoped_query ~dialect ~cardinality:One slots query |> or_raise
  in
  let query_optional query =
    compile_scoped_query ~dialect ~cardinality:Optional slots query |> or_raise
  in
  let expect_one query =
    compile_scoped_query ~dialect ~cardinality:One slots query |> or_raise
  in
  let expect_optional query =
    compile_scoped_query ~dialect ~cardinality:Optional slots query |> or_raise
  in
  let command command = compile_scoped_command ~dialect slots command |> or_raise in
  { expr
  ; optional_expr
  ; column
  ; non_negative_int
  ; non_negative_int_opt
  ; query_many
  ; query_one
  ; query_optional
  ; expect_one
  ; expect_optional
  ; command
  }
;;

let with_parameters ~dialect build =
  Parameters.unwrap (build ~params:(make_parameters ~dialect (ref [])))
;;

let no_parameters
  : type requirements supports.
    dialect:(requirements, supports) Dialect.supports
    -> (unit, requirements, supports) parameters
  =
  fun ~dialect -> make_parameters ~dialect (ref [])
;;

let query_many ~dialect query = (no_parameters ~dialect).query_many query
let query_one ~dialect query = (no_parameters ~dialect).query_one query
let query_optional ~dialect query = (no_parameters ~dialect).query_optional query
let expect_one ~dialect query = (no_parameters ~dialect).expect_one query
let expect_optional ~dialect query = (no_parameters ~dialect).expect_optional query
let command ~dialect statement = (no_parameters ~dialect).command statement
let choose ~when_ ~if_true ~if_false = Choose { when_; if_true; if_false }

let choose_dialect
  : type input output.
    postgresql:(input, output, [ `Postgresql ]) t
    -> sqlite:(input, output, [ `Sqlite ]) t
    -> (input, output, Dialect.both) t
  =
  fun ~postgresql ~sqlite -> Choose_dialect { postgresql; sqlite }
;;

module Dynamic = struct
  let query_many ~dialect build = Dynamic_query { cardinality = Many; dialect; build }
  let query_one ~dialect build = Dynamic_query { cardinality = One; dialect; build }

  let query_optional ~dialect build =
    Dynamic_query { cardinality = Optional; dialect; build }
  ;;

  let expect_one ~dialect build = Dynamic_query { cardinality = One; dialect; build }

  let expect_optional ~dialect build =
    Dynamic_query { cardinality = Optional; dialect; build }
  ;;

  let command ~dialect build = Dynamic_command { dialect; build }
end

let same_dialect left right =
  match left, right with
  | Dialect.Postgresql, Dialect.Postgresql | Dialect.Sqlite, Dialect.Sqlite -> true
  | Dialect.Postgresql, Dialect.Sqlite | Dialect.Sqlite, Dialect.Postgresql -> false
;;

let supports_dialect
  : type requirements supports.
    (requirements, supports) Dialect.supports -> Dialect.t -> bool
  =
  fun witness dialect ->
  match witness with
  | Dialect.Portable -> true
  | Dialect.Concrete_postgresql -> same_dialect Dialect.Postgresql dialect
  | Dialect.Concrete_sqlite -> same_dialect Dialect.Sqlite dialect
;;

let find_plan : type plan supports. Dialect.t -> (plan, supports) plan_set -> plan option =
  fun dialect -> function
  | Portable_plans { postgresql_plan; sqlite_plan } ->
    Some
      (match dialect with
       | Dialect.Postgresql -> postgresql_plan
       | Dialect.Sqlite -> sqlite_plan)
  | Postgresql_plan plan ->
    (match dialect with
     | Dialect.Postgresql -> Some plan
     | Dialect.Sqlite -> None)
  | Sqlite_plan plan ->
    (match dialect with
     | Dialect.Postgresql -> None
     | Dialect.Sqlite -> Some plan)
;;

let select_plan
  : type plan supports. supports Dialect.Selected.t -> (plan, supports) plan_set -> plan
  =
  fun dialect plans ->
  match plans, dialect with
  | Portable_plans { postgresql_plan; _ }, Dialect.Selected.Postgresql -> postgresql_plan
  | Portable_plans { sqlite_plan; _ }, Dialect.Selected.Sqlite -> sqlite_plan
  | Postgresql_plan plan, Dialect.Selected.Postgresql -> plan
  | Sqlite_plan plan, Dialect.Selected.Sqlite -> plan
;;

let find_slot id slots = List.find slots ~f:(fun (Slot slot) -> Int.equal id slot.id)

let bind_parameter input slots = function
  | Ast.Value packed_value -> Ok { packed_value; name = None }
  | Ast.Slot { id; _ } ->
    (match find_slot id slots with
     | None -> Error (Binding { name = None; message = Unknown_parameter_slot })
     | Some (Slot slot) ->
       let value = slot.get input in
       (match slot.validate value with
        | None ->
          Ok { packed_value = Db_type.Value (slot.db_type, value); name = slot.name }
        | Some message -> Error (Binding { name = slot.name; message })))
;;

let bind_parameters input slots parameters =
  List.map parameters ~f:(bind_parameter input slots) |> Result.all
;;

let rec resolve_details
  : type input output supports.
    dialect:Dialect.t
    -> input
    -> (input, output, supports) t
    -> (output resolved_plan, resolve_error) Result.t
  =
  fun ~dialect input statement ->
  match statement with
  | Dynamic_query { cardinality; dialect = witness; build } ->
    let open Result.Let_syntax in
    let%bind () =
      if supports_dialect witness dialect then
        Ok ()
      else
        Error Dialect_mismatch
    in
    let%bind plan =
      compile_query ~dialect (ref []) (build input)
      |> Result.map_error ~f:(fun error -> Compilation error)
    in
    (match dialect with
     | Dialect.Postgresql ->
       resolve_details
         ~dialect
         input
         (Query { cardinality; plans = Postgresql_plan plan })
     | Dialect.Sqlite ->
       resolve_details ~dialect input (Query { cardinality; plans = Sqlite_plan plan }))
  | Dynamic_command { dialect = witness; build } ->
    let open Result.Let_syntax in
    let%bind () =
      if supports_dialect witness dialect then
        Ok ()
      else
        Error Dialect_mismatch
    in
    let%bind plan =
      compile_command ~dialect (ref []) (build input)
      |> Result.map_error ~f:(fun error -> Compilation error)
    in
    (match dialect with
     | Dialect.Postgresql ->
       resolve_details ~dialect input (Command { plans = Postgresql_plan plan })
     | Dialect.Sqlite ->
       resolve_details ~dialect input (Command { plans = Sqlite_plan plan }))
  | Choose { when_; if_true; if_false } ->
    resolve_details
      ~dialect
      input
      (if when_ input then
         if_true
       else
         if_false)
  | Choose_dialect { postgresql; sqlite } ->
    (match dialect with
     | Dialect.Postgresql -> resolve_details ~dialect input postgresql
     | Dialect.Sqlite -> resolve_details ~dialect input sqlite)
  | Query { cardinality; plans } ->
    (match find_plan dialect plans with
     | None -> Error Dialect_mismatch
     | Some plan ->
       Result.map
         (bind_parameters input plan.slots plan.compiled.parameters)
         ~f:(fun parameters ->
           Resolved_query { cardinality; compiled = plan.compiled; parameters }))
  | Command { plans } ->
    (match find_plan dialect plans with
     | None -> Error Dialect_mismatch
     | Some plan ->
       Result.map
         (bind_parameters input plan.slots plan.compiled.parameters)
         ~f:(fun parameters -> Resolved_command { compiled = plan.compiled; parameters }))
;;

let resolve
  : type input output supports.
    dialect:Dialect.t
    -> input
    -> (input, output, supports) t
    -> (output execution, resolve_error) Result.t
  =
  fun ~dialect input statement ->
  Result.map (resolve_details ~dialect input statement) ~f:(function
    | Resolved_query { cardinality; compiled; parameters } ->
      let parameters = List.map parameters ~f:(fun bound -> bound.packed_value) in
      let compiled =
        Compiled_query.create
          ~dialect:compiled.dialect
          ~template:compiled.template
          ~parameters
          ~projection:compiled.projection
          ~shape:compiled.shape
      in
      Query_execution { cardinality; compiled }
    | Resolved_command { compiled; parameters } ->
      let parameters = List.map parameters ~f:(fun bound -> bound.packed_value) in
      Compiled_command.create
        ~dialect:compiled.dialect
        ~template:compiled.template
        ~parameters
        ~shape:compiled.shape
      |> fun compiled -> Command_execution compiled)
;;

let rec tree_of
  : type input output supports. (input, output, supports) t -> statement_tree
  = function
  | Query _ -> Leaf { kind = `Query; mode = `Static }
  | Command _ -> Leaf { kind = `Command; mode = `Static }
  | Dynamic_query _ -> Leaf { kind = `Query; mode = `Dynamic }
  | Dynamic_command _ -> Leaf { kind = `Command; mode = `Dynamic }
  | Choose { if_true; if_false; _ } ->
    Input_choice
      { selected = None; if_true = tree_of if_true; if_false = tree_of if_false }
  | Choose_dialect { postgresql; sqlite } ->
    Dialect_choice
      { selected = None; postgresql = tree_of postgresql; sqlite = tree_of sqlite }
;;

let rec resolve_for_inspection
  : type input output supports.
    dialect:Dialect.t
    -> input
    -> (input, output, supports) t
    -> (output resolved_plan * statement_tree, resolve_error) Result.t
  =
  fun ~dialect input statement ->
  match statement with
  | Choose { when_; if_true; if_false } ->
    let selected = when_ input in
    let branch =
      if selected then
        if_true
      else
        if_false
    in
    let open Result.Let_syntax in
    let%map resolved, chosen_tree = resolve_for_inspection ~dialect input branch in
    ( resolved
    , Input_choice
        { selected = Some selected
        ; if_true =
            (if selected then
               chosen_tree
             else
               tree_of if_true)
        ; if_false =
            (if selected then
               tree_of if_false
             else
               chosen_tree)
        } )
  | Choose_dialect { postgresql; sqlite } ->
    (match dialect with
     | Dialect.Postgresql ->
       Result.map
         (resolve_for_inspection ~dialect input postgresql)
         ~f:(fun (resolved, chosen_tree) ->
           ( resolved
           , Dialect_choice
               { selected = Some Dialect.Postgresql
               ; postgresql = chosen_tree
               ; sqlite = tree_of sqlite
               } ))
     | Dialect.Sqlite ->
       Result.map
         (resolve_for_inspection ~dialect input sqlite)
         ~f:(fun (resolved, chosen_tree) ->
           ( resolved
           , Dialect_choice
               { selected = Some Dialect.Sqlite
               ; postgresql = tree_of postgresql
               ; sqlite = chosen_tree
               } )))
  | Query _ ->
    Result.map (resolve_details ~dialect input statement) ~f:(fun resolved ->
      resolved, Leaf { kind = `Query; mode = `Static })
  | Command _ ->
    Result.map (resolve_details ~dialect input statement) ~f:(fun resolved ->
      resolved, Leaf { kind = `Command; mode = `Static })
  | Dynamic_query _ ->
    Result.map (resolve_details ~dialect input statement) ~f:(fun resolved ->
      resolved, Leaf { kind = `Query; mode = `Dynamic })
  | Dynamic_command _ ->
    Result.map (resolve_details ~dialect input statement) ~f:(fun resolved ->
      resolved, Leaf { kind = `Command; mode = `Dynamic })
;;

let rec sql_without_input
  : type input output supports.
    dialect:supports Dialect.Selected.t
    -> (input, output, supports) t
    -> (string, sql_error) Result.t
  =
  fun ~dialect statement ->
  match statement with
  | Query { plans; _ } ->
    let plan = select_plan dialect plans in
    Ok (Template.to_sql ~dialect:plan.compiled.dialect plan.compiled.template)
  | Command { plans } ->
    let plan = select_plan dialect plans in
    Ok (Template.to_sql ~dialect:plan.compiled.dialect plan.compiled.template)
  | Choose_dialect { postgresql; sqlite } ->
    (match dialect with
     | Dialect.Selected.Postgresql ->
       sql_without_input ~dialect:Dialect.Selected.postgresql postgresql
     | Dialect.Selected.Sqlite ->
       sql_without_input ~dialect:Dialect.Selected.sqlite sqlite)
  | Dynamic_query _ | Dynamic_command _ -> Error Dynamic_input_required
  | Choose _ -> Error Dynamic_input_required
;;

let sql
  : type input output supports.
    dialect:supports Dialect.Selected.t
    -> ?input:input
    -> (input, output, supports) t
    -> (string, sql_error) Result.t
  =
  fun ~dialect ?input statement ->
  let concrete_dialect = Dialect.selected_dialect dialect in
  match input with
  | Some input ->
    (match resolve ~dialect:concrete_dialect input statement with
     | Ok (Query_execution execution) -> Ok (Compiled_query.sql execution.compiled)
     | Ok (Command_execution execution) -> Ok (Compiled_command.sql execution)
     | Error Dialect_mismatch -> Error (Unsupported_dialect concrete_dialect)
     | Error (Binding error) -> Error (Invalid_parameter error)
     | Error (Compilation error) -> Error (Compilation_error error))
  | None -> sql_without_input ~dialect statement
;;

let sql_exn ~dialect ?input statement =
  match sql ~dialect ?input statement with
  | Ok sql -> sql
  | Error (Compilation_error error) -> raise (Definition_error error)
  | Error error -> raise (Sql_error error)
;;

let placeholder dialect position =
  match dialect with
  | Dialect.Postgresql -> "$" ^ Int.to_string position
  | Dialect.Sqlite -> "?" ^ Int.to_string position
;;

let rec encode_diagnostic_value
  : type value.
    Dialect.t -> value Db_type.t -> value -> (parameter_value * string, string) Result.t
  =
  fun dialect db_type value ->
  let encoded value storage_class = Ok (Encoded value, storage_class) in
  let open Db_type in
  match view db_type with
  | Bool ->
    encoded
      (match dialect with
       | Dialect.Postgresql -> Bool.to_string value
       | Dialect.Sqlite ->
         if value then
           "1"
         else
           "0")
      "INTEGER"
  | Int -> encoded (Int.to_string value) "INTEGER"
  | Int64 -> encoded (Int64.to_string value) "INTEGER"
  | Float -> encoded (Stdlib.Printf.sprintf "%.17g" value) "REAL"
  | Numeric -> encoded (Decimal.to_string value) "TEXT"
  | Text -> encoded value "TEXT"
  | Bytes ->
    Result.map (Db_type.pg_text_encode db_type value) ~f:(fun value ->
      Encoded value, "BLOB")
  | Date -> encoded (Date.to_string value) "TEXT"
  | Timestamp -> encoded (Ptime.to_rfc3339 value) "TEXT"
  | Uuid -> encoded (Uuid.to_string value) "TEXT"
  | Named { repr; _ } -> encode_diagnostic_value dialect repr value
  | Array { encode; _ } ->
    Result.map (encode value) ~f:(fun value -> Encoded value, "TEXT")
  | Option inner ->
    (match value with
     | None -> Ok (Null, "NULL")
     | Some value -> encode_diagnostic_value dialect inner value)
  | Map { repr; encode; _ } ->
    let open Result.Let_syntax in
    let%bind value = encode value in
    encode_diagnostic_value dialect repr value
;;

let parameter_info ~dialect ~position ~name ~db_type ~value ~storage_class =
  { position
  ; placeholder = placeholder dialect position
  ; name
  ; db_type = Db_type.name db_type
  ; dialect_type =
      (match dialect with
       | Dialect.Postgresql -> Some (Db_type.postgresql_type_name db_type)
       | Dialect.Sqlite -> storage_class)
  ; value
  }
;;

let unbound_parameter_info ~dialect ~slots ~position parameter =
  match parameter with
  | Ast.Value (Db_type.Value (db_type, _)) ->
    Ok
      (parameter_info
         ~dialect
         ~position
         ~name:None
         ~db_type
         ~value:None
         ~storage_class:None)
  | Ast.Slot { id; db_type = Db_type.Pack db_type } ->
    (match find_slot id slots with
     | None ->
       Error
         (Statement_error
            (Invalid_parameter { name = None; message = Unknown_parameter_slot }))
     | Some (Slot slot) ->
       Ok
         (parameter_info
            ~dialect
            ~position
            ~name:slot.name
            ~db_type
            ~value:None
            ~storage_class:None))
;;

let bound_parameter_info ~dialect ~position bound =
  let (Db_type.Value (db_type, value)) = bound.packed_value in
  let open Result.Let_syntax in
  let%map value, storage_class =
    encode_diagnostic_value dialect db_type value
    |> Result.map_error ~f:(fun message ->
      Codec_error { position; name = bound.name; message })
  in
  parameter_info
    ~dialect
    ~position
    ~name:bound.name
    ~db_type
    ~value:(Some value)
    ~storage_class:(Some storage_class)
;;

let row_cardinality : type row output. (row, output) cardinality -> row_cardinality =
  function
  | Many -> `Many
  | One -> `One
  | Optional -> `Optional
;;

let output_columns ~dialect (Projection.Erased projection) =
  List.zip_exn (Projection.types projection) (Projection.expressions projection)
  |> List.mapi ~f:(fun index (Db_type.Pack db_type, expression) ->
    { position = index + 1
    ; name =
        (match expression with
         | Ast.Column { name; _ } -> Some (Identifier.to_string name)
         | _ -> None)
    ; db_type = Db_type.name db_type
    ; dialect_type =
        (match dialect with
         | Dialect.Postgresql -> Some (Db_type.postgresql_type_name db_type)
         | Dialect.Sqlite -> None)
    })
;;

let query_output ~dialect ~cardinality projection =
  Query_output
    { cardinality = row_cardinality cardinality
    ; columns = output_columns ~dialect projection
    }
;;

let make_inspection ~dialect ~parameters ~output ~tree =
  { dialect; parameters; output; tree }
;;

let rec inspect_without_input
  : type input output supports.
    dialect:supports Dialect.Selected.t
    -> (input, output, supports) t
    -> (string * inspection, inspection_error) Result.t
  =
  fun ~dialect statement ->
  let concrete_dialect = Dialect.selected_dialect dialect in
  let describe ~template ~parameters:ast_parameters ~slots ~output ~tree =
    let open Result.Let_syntax in
    let%map parameters =
      List.mapi ast_parameters ~f:(fun index parameter ->
        unbound_parameter_info
          ~dialect:concrete_dialect
          ~slots
          ~position:(index + 1)
          parameter)
      |> Result.all
    in
    ( Template.to_sql ~dialect:concrete_dialect template
    , make_inspection ~dialect:concrete_dialect ~parameters ~output ~tree )
  in
  match statement with
  | Query { cardinality; plans } ->
    let plan = select_plan dialect plans in
    describe
      ~template:plan.compiled.template
      ~parameters:plan.compiled.parameters
      ~slots:plan.slots
      ~output:
        (query_output ~dialect:concrete_dialect ~cardinality plan.compiled.projection)
      ~tree:(Leaf { kind = `Query; mode = `Static })
  | Command { plans } ->
    let plan = select_plan dialect plans in
    describe
      ~template:plan.compiled.template
      ~parameters:plan.compiled.parameters
      ~slots:plan.slots
      ~output:Command_output
      ~tree:(Leaf { kind = `Command; mode = `Static })
  | Choose_dialect { postgresql; sqlite } ->
    (match dialect with
     | Dialect.Selected.Postgresql ->
       Result.map
         (inspect_without_input ~dialect:Dialect.Selected.postgresql postgresql)
         ~f:(fun (sql, inspection) ->
           ( sql
           , { inspection with
               tree =
                 Dialect_choice
                   { selected = Some Dialect.Postgresql
                   ; postgresql = inspection.tree
                   ; sqlite = tree_of sqlite
                   }
             } ))
     | Dialect.Selected.Sqlite ->
       Result.map
         (inspect_without_input ~dialect:Dialect.Selected.sqlite sqlite)
         ~f:(fun (sql, inspection) ->
           ( sql
           , { inspection with
               tree =
                 Dialect_choice
                   { selected = Some Dialect.Sqlite
                   ; postgresql = tree_of postgresql
                   ; sqlite = inspection.tree
                   }
             } )))
  | Dynamic_query _ | Dynamic_command _ | Choose _ ->
    Error (Statement_error Dynamic_input_required)
;;

let inspect
  : type input output supports.
    dialect:supports Dialect.Selected.t
    -> ?input:input
    -> (input, output, supports) t
    -> (string * inspection, inspection_error) Result.t
  =
  fun ~dialect ?input statement ->
  match input with
  | None -> inspect_without_input ~dialect statement
  | Some input ->
    let concrete_dialect = Dialect.selected_dialect dialect in
    let open Result.Let_syntax in
    let%bind resolved, tree =
      resolve_for_inspection ~dialect:concrete_dialect input statement
      |> Result.map_error ~f:(function
        | Dialect_mismatch -> Statement_error (Unsupported_dialect concrete_dialect)
        | Binding error -> Statement_error (Invalid_parameter error)
        | Compilation error -> Statement_error (Compilation_error error))
    in
    let template, output, bound_parameters =
      match resolved with
      | Resolved_query { cardinality; compiled; parameters } ->
        ( compiled.template
        , query_output ~dialect:concrete_dialect ~cardinality compiled.projection
        , parameters )
      | Resolved_command { compiled; parameters } ->
        compiled.template, Command_output, parameters
    in
    let%map parameters =
      List.mapi bound_parameters ~f:(fun index bound ->
        bound_parameter_info ~dialect:concrete_dialect ~position:(index + 1) bound)
      |> Result.all
    in
    ( Template.to_sql ~dialect:concrete_dialect template
    , make_inspection ~dialect:concrete_dialect ~parameters ~output ~tree )
;;

let inspect_exn ~dialect ?input statement =
  match inspect ~dialect ?input statement with
  | Ok inspection -> inspection
  | Error (Statement_error (Compilation_error error)) -> raise (Definition_error error)
  | Error (Statement_error error) -> raise (Sql_error error)
  | Error (Codec_error _ as error) -> raise (Inspection_error error)
;;
